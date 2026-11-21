#import "PMOSMediaView.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>

// ImageIO access is confined to this serial queue, including opening the source.
static dispatch_queue_t PMOSGIFQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("phimod.chapter.gif", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@interface PMOSGIFDecoder : NSObject
- (UIImage *)frameAtIndex:(size_t)index path:(NSString *)path delay:(double *)delay count:(size_t *)count;
@end

@implementation PMOSGIFDecoder {
    CGImageSourceRef _source;
    size_t _count;
}
- (UIImage *)frameAtIndex:(size_t)index path:(NSString *)path delay:(double *)delay count:(size_t *)count {
    if (!_source) {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue] > 32ull * 1024 * 1024) return nil;
        NSURL *url = [NSURL fileURLWithPath:path];
        NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
        _source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)options);
        if (!_source || ![(__bridge NSString *)CGImageSourceGetType(_source) isEqualToString:@"com.compuserve.gif"]) return nil;
        _count = CGImageSourceGetCount(_source);
    }
    if (index >= _count || _count > 4096) return nil;
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(_source, index, NULL));
    NSInteger width = [props[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
    NSInteger height = [props[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
    if (width < 1 || height < 1 || width > 4096 || height > 4096) return nil;
    NSDictionary *gif = props[(__bridge NSString *)kCGImagePropertyGIFDictionary];
    double seconds = [gif[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
    if (!(seconds > 0)) seconds = [gif[(__bridge NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
    *delay = std::isfinite(seconds) && seconds > 0 ? seconds : 0.1;
    *count = _count;
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1024,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef frame = CGImageSourceCreateThumbnailAtIndex(_source, index, (__bridge CFDictionaryRef)options);
    CGImageSourceRemoveCacheAtIndex(_source, index);
    if (!frame) return nil;
    UIImage *image = [UIImage imageWithCGImage:frame];
    CGImageRelease(frame);
    return image;
}
- (void)dealloc {
    if (_source) CFRelease(_source);
}
@end

@implementation PMOSMediaView {
    NSString *_path;
    BOOL _loop, _playing, _active;
    UIImageView *_image;
    PMOSGIFDecoder *_decoder;
    NSTimer *_timer;
    id _endObserver;
}
+ (Class)layerClass { return AVPlayerLayer.class; }

- (instancetype)initWithPath:(NSString *)path loop:(BOOL)loop fill:(BOOL)fill {
    if ((self = [super initWithFrame:CGRectZero])) {
        _path = [path copy];
        _loop = loop;
        _playing = YES;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        ((AVPlayerLayer *)self.layer).videoGravity = fill ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
        _image = [[UIImageView alloc] initWithFrame:self.bounds];
        _image.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _image.contentMode = fill ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        [self addSubview:_image];
    }
    return self;
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    [self updatePlayback];
}
- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updatePlayback];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updatePlayback];
}
- (void)updatePlayback {
    BOOL active = _playing && !self.hidden && self.window != nil;
    if (active == _active) return;
    _active = active;
    if (!active) {
        [self clearMedia];
        return;
    }
    if (!_path.isAbsolutePath) return;
    NSString *ext = _path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"gif"]) {
        _decoder = [PMOSGIFDecoder new];
        [self requestFrame:0 displayAt:0];
    } else if ([ext isEqualToString:@"mp4"]) {
        [self startVideo];
    }
}

// Prefetch one frame while the current frame is visible. A late decode extends
// the current frame's dwell time. It never queues catch-up frames.
- (void)requestFrame:(size_t)index displayAt:(CFTimeInterval)deadline {
    __weak PMOSGIFDecoder *session = _decoder;
    __weak PMOSMediaView *weakView = self;
    NSString *path = _path;
    dispatch_async(PMOSGIFQueue(), ^{
        @autoreleasepool {
            PMOSGIFDecoder *decoder = session;
            if (!decoder) return;
            double delay = 0;
            size_t count = 0;
            UIImage *frame = [decoder frameAtIndex:index path:path delay:&delay count:&count];
            dispatch_async(dispatch_get_main_queue(), ^{
                PMOSMediaView *view = weakView;
                if (!view || view->_decoder != decoder) return;
                if (!frame) {
                    [view clearMedia];
                    return;
                }
                [view scheduleFrame:frame index:index count:count delay:delay displayAt:deadline];
            });
        }
    });
}

- (void)scheduleFrame:(UIImage *)frame index:(size_t)index count:(size_t)count
                delay:(double)delay displayAt:(CFTimeInterval)deadline {
    __weak PMOSMediaView *weakView = self;
    PMOSGIFDecoder *session = _decoder;
    void (^present)(NSTimer *) = ^(NSTimer *timer) {
        PMOSMediaView *view = weakView;
        if (!view || view->_decoder != session) return;
        view->_timer = nil;
        view->_image.image = frame;
        if (count == 1 || (index + 1 == count && !view->_loop)) {
            view->_decoder = nil;
            return;
        }
        [view requestFrame:(index + 1) % count displayAt:CACurrentMediaTime() + delay];
    };
    double remaining = deadline - CACurrentMediaTime();
    if (remaining <= 0) {
        present(nil);
    } else {
        _timer = [NSTimer timerWithTimeInterval:remaining repeats:NO block:present];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

- (void)startVideo {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:_path error:nil];
    if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || ![attrs[NSFileSize] unsignedLongLongValue]) return;
    AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:_path]];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    ((AVPlayerLayer *)self.layer).player = player;
    if (_loop && player.currentItem) {
        __weak AVPlayer *weakPlayer = player;
        _endObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
            object:player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                AVPlayer *current = weakPlayer;
                if (!current || current.currentItem != note.object) return;
                [current seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        AVPlayer *active = weakPlayer;
                        if (finished && active.currentItem == note.object) [active play];
                    });
                }];
            }];
    }
    [player play];
}

- (void)clearMedia {
    [_timer invalidate];
    _timer = nil;
    _decoder = nil;
    _image.image = nil;
    if (_endObserver) [NSNotificationCenter.defaultCenter removeObserver:_endObserver];
    _endObserver = nil;
    AVPlayerLayer *layer = (AVPlayerLayer *)self.layer;
    [layer.player pause];
    [layer.player replaceCurrentItemWithPlayerItem:nil];
    layer.player = nil;
}
- (void)dealloc {
    [_timer invalidate];
    if (_endObserver) [NSNotificationCenter.defaultCenter removeObserver:_endObserver];
}
@end
