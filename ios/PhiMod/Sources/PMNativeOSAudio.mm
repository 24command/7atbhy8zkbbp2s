#import "PMNativeOSAudio.h"
#import <AVFoundation/AVFoundation.h>
#if !defined(PM_NATIVE_OS_AUDIO_HOST_TEST)
#import <UIKit/UIKit.h>
#endif
#include "PMNativeOSAudioTimeline.hpp"
#include "../Core/PMAudioFileType.hpp"
#include <cerrno>
#include <climits>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
#if defined(PM_NATIVE_OS_AUDIO_HOST_TEST)
// macOS Foundation-only test host. This switch replaces ONLY application
// lifecycle notification signals; AVAudioPlayer and all file/decoder code remain real.
BOOL hostApplicationActive = YES;
NSString *applicationResignNotification() { return @"PhiMod.AudioHost.WillResignActive"; }
NSString *applicationActiveNotification() { return @"PhiMod.AudioHost.DidBecomeActive"; }
BOOL applicationInactive() { return !hostApplicationActive; }
NSString *interruptionNotification() { return @"PhiMod.AudioHost.Interruption"; }
NSString *interruptionTypeKey() { return @"type"; }
NSString *interruptionOptionKey() { return @"options"; }
// Test TU includes this implementation, so no production/exported test hook.
[[maybe_unused]] void injectHostApplicationActive(BOOL active) {
    NSCAssert(NSThread.isMainThread, @"Audio host lifecycle injection is main-thread-only");
    hostApplicationActive = active;
    [NSNotificationCenter.defaultCenter postNotificationName:active ? applicationActiveNotification() : applicationResignNotification()
                                                     object:nil];
}
#else
NSString *applicationResignNotification() { return UIApplicationWillResignActiveNotification; }
NSString *applicationActiveNotification() { return UIApplicationDidBecomeActiveNotification; }
BOOL applicationInactive() { return UIApplication.sharedApplication.applicationState != UIApplicationStateActive; }
NSString *interruptionNotification() { return AVAudioSessionInterruptionNotification; }
NSString *interruptionTypeKey() { return AVAudioSessionInterruptionTypeKey; }
NSString *interruptionOptionKey() { return AVAudioSessionInterruptionOptionKey; }
#endif
constexpr NSUInteger FileLimit = 32u * 1024u * 1024u;
constexpr NSUInteger TotalLimit = 64u * 1024u * 1024u;
NSError *audioError(NSString *message, NSString *src = nil, NSError *underlying = nil) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey:message} mutableCopy];
    if (src) info[@"src"] = src;
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:@"PhiMod.NativeOSAudio" code:1 userInfo:info];
}
bool text(id value, NSUInteger bytes, bool empty = false) {
    if (![value isKindOfClass:NSString.class]) return false;
    NSString *s = value;
    return (empty || s.length) && [s canBeConvertedToEncoding:NSUTF8StringEncoding] &&
        [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= bytes &&
        [s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}
bool number(id value, double minimum, double maximum) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return false;
    double d = [value doubleValue];
    return std::isfinite(d) && d >= minimum && d <= maximum;
}
bool basename(id value) {
    if (!text(value, 255)) return false;
    NSString *s = value;
    return ![s hasPrefix:@"."] && [s isEqualToString:s.lastPathComponent] &&
        [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]].location == NSNotFound &&
        [@[@"m4a", @"wav", @"mp3", @"aac", @"caf", @"aiff"] containsObject:s.pathExtension.lowercaseString];
}
struct FD {
    int fd;
    explicit FD(int value) : fd(value) {}
    ~FD() { if (fd >= 0) close(fd); }
    FD(const FD &) = delete;
    FD &operator=(const FD &) = delete;
};
NSString *containerSpelling(NSString *s) {
    return [s hasPrefix:@"/var/"] ? [@"/private" stringByAppendingString:s] : s;
}
// Pin the trusted container, then reject links in EVERY author-controlled
// component. Never standardize/resolve symlinks before this descriptor walk.
int openMedia(NSString *chapter) {
    if (!text(chapter, 4096)) return -1;
    NSString *home = containerSpelling(NSHomeDirectory());
    chapter = containerSpelling(chapter);
    if (![home hasPrefix:@"/"] || [home isEqualToString:@"/"] ||
        ![chapter hasPrefix:[home stringByAppendingString:@"/"]]) return -1;
    NSString *relative = [[chapter substringFromIndex:home.length + 1] stringByAppendingString:@"/os-media"];
    NSArray<NSString *> *parts = [relative componentsSeparatedByString:@"/"];
    for (NSString *part in parts)
        if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."] ||
            [part containsString:@"\\"] || [part containsString:@":"]) return -1;
    int fd = open(home.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    for (NSString *part in parts) {
        int next = openat(fd, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close(fd);
        if (next < 0) return -1;
        fd = next;
    }
    return fd;
}
NSData *readAudio(int directory, NSString *src, NSUInteger remaining, NSError **error) {
    FD file(directory < 0 ? -1 : openat(directory, src.fileSystemRepresentation,
        O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    struct stat before{}, after{};
    if (file.fd < 0 || fstat(file.fd, &before) || !S_ISREG(before.st_mode) ||
        before.st_size <= 0 || static_cast<uint64_t>(before.st_size) > FileLimit ||
        static_cast<uint64_t>(before.st_size) > remaining) {
        *error = audioError(@"Audio missing, linked, nonregular or exceeds 32 MiB/file or 64 MiB/visit", src);
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:static_cast<NSUInteger>(before.st_size)];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t n = read(file.fd, static_cast<char *>(data.mutableBytes) + offset, data.length - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        offset += static_cast<NSUInteger>(n);
    }
    char extra;
    ssize_t tail;
    do { tail = read(file.fd, &extra, 1); } while (tail < 0 && errno == EINTR);
    if (offset != data.length || tail != 0 || fstat(file.fd, &after) ||
        before.st_size != after.st_size || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec ||
        before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec ||
        before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec ||
        before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec) {
        *error = audioError(@"Audio changed or could not be read completely", src);
        return nil;
    }
    const auto *p = static_cast<const unsigned char *>(data.bytes);
    const char *kind = phimod::audioFileExtension(p, data.length);
    // The shared helper has no CAF/ADTS entries; extend recognition locally.
    if (!*kind && data.length >= 8 && !std::memcmp(p, "caff", 4)) kind = "caf";
    if (!*kind && data.length >= 7 && p[0] == 0xff && (p[1] & 0xf6) == 0xf0 &&
        ((p[2] >> 2) & 15) < 13) kind = "aac";
    if (!*kind || ![src.pathExtension.lowercaseString isEqualToString:[NSString stringWithUTF8String:kind]]) {
        *error = audioError(@"Audio signature does not match its supported extension", src);
        return nil;
    }
    return data;
}
NSString *playerKey(const pmnativeosaudio::Cue &c, bool intro = false) {
    return [NSString stringWithFormat:@"%d:%d:%s", static_cast<int>(c.channel), intro ? 1 : 0,
            intro ? c.introSrc.c_str() : c.src.c_str()];
}
// Non-owning, main-thread adapter. The runtime retains both players while a
// transport is live; the worker-created pool owns decoded bytes between visits.
struct NativePlayer {
    __unsafe_unretained AVAudioPlayer *player;
    double time() const { return player.currentTime; }
    double deviceTime() const { return player.deviceCurrentTime; }
    bool playing() const { return player.isPlaying; }
    void seek(double time) { player.currentTime = time; }
    void loops(bool loop) { player.numberOfLoops = loop ? -1 : 0; }
    void stop() { [player stop]; }
    bool prepare() { return [player prepareToPlay]; }
    bool play() { return [player play]; }
    bool playAt(double time) { return [player playAtTime:time]; }
};
}

@interface PMNativeOSAudio ()
- (void)reconcile;
- (void)installObservers;
- (void)samplePlaybackPositions;
- (void)clearChannel:(int)channel;
@end

@implementation PMNativeOSAudio {
    pmnativeosaudio::Timeline _timeline;
    NSMutableDictionary<NSString *, AVAudioPlayer *> *_players;
    NSArray<NSError *> *_diagnostics;
    NSError *_lastPlaybackError;
    AVAudioPlayer *_playing[2], *_introPlaying[2];
    uint64_t _serials[2];
    pmnativeosaudio::Transport _transports[2];
    BOOL _explicitSuspended, _background, _interrupted, _resumeBlocked, _ownsBGM;
    NSMutableArray *_observers;
}
- (instancetype)initWithCues:(NSArray<NSDictionary *> *)cues chapterDir:(NSString *)chapterDir error:(NSError **)error {
    if (error) *error = nil;
    if (!(self = [super init])) return nil;
    if (NSThread.isMainThread || ![cues isKindOfClass:NSArray.class] || cues.count > 64 || !text(chapterDir, 4096)) {
        if (error) *error = audioError(@"OS audio requires a worker queue, chapter directory and at most 64 cues");
        return nil;
    }
    std::vector<pmnativeosaudio::Cue> parsed;
    for (id value in cues) {
        if (![value isKindOfClass:NSDictionary.class]) {
            if (error) *error = audioError(@"Audio cue must be a dictionary");
            return nil;
        }
        NSDictionary *d = value;
        id event = d[@"event"] ?: @"page", channel = d[@"channel"] ?: @"effect";
        id start = d[@"start"] ?: @0, duration = d[@"duration"] ?: @0, volume = d[@"volume"] ?: @1;
        id loop = d[@"loop"] ?: @NO, target = d[@"target"] ?: @"", introSrc = d[@"introSrc"] ?: @"";
        const double maximum = std::numeric_limits<double>::max();
        bool valid = number(d[@"screen"], 0, INT_MAX) && [d[@"screen"] doubleValue] == std::floor([d[@"screen"] doubleValue]) &&
            basename(d[@"src"]) && text(introSrc, 255, true) && (![introSrc length] || basename(introSrc)) && text(event, 4) && ([(NSString *)event isEqualToString:@"page"] || [(NSString *)event isEqualToString:@"tap"]) &&
            text(channel, 6) && ([(NSString *)channel isEqualToString:@"bgm"] || [(NSString *)channel isEqualToString:@"effect"]) &&
            number(start, 0, maximum) && number(duration, 0, maximum) && number(volume, 0, 1) &&
            std::isfinite([start doubleValue] + [duration doubleValue]) && text(target, 63, true) &&
            [loop isKindOfClass:NSNumber.class] && ([loop doubleValue] == 0 || [loop doubleValue] == 1);
        if (!valid || ([(NSString *)event isEqualToString:@"tap"] && ([start doubleValue] != 0 || [loop boolValue])) ||
            ([(NSString *)event isEqualToString:@"page"] && [target length]) ||
            ([introSrc length] && (![loop boolValue] || ![event isEqualToString:@"page"] || [introSrc isEqualToString:d[@"src"]]))) {
            if (error) *error = audioError(@"Invalid audio cue fields; introSrc requires page/loop and a distinct src");
            return nil;
        }
        pmnativeosaudio::Cue c;
        c.screen = [d[@"screen"] intValue]; c.src = [d[@"src"] UTF8String]; c.introSrc = [introSrc UTF8String]; c.target = [target UTF8String];
        c.event = [event isEqualToString:@"tap"] ? pmnativeosaudio::Event::Tap : pmnativeosaudio::Event::Page;
        c.channel = [channel isEqualToString:@"bgm"] ? pmnativeosaudio::Channel::BGM : pmnativeosaudio::Channel::Effect;
        c.start = [start doubleValue]; c.duration = [duration doubleValue]; c.volume = [volume doubleValue]; c.loop = [loop boolValue];
        for (const auto &previous : parsed) if (previous.screen == c.screen && previous.event == c.event && previous.channel == c.channel &&
            (c.event == pmnativeosaudio::Event::Page ? previous.start == c.start : previous.target == c.target)) {
            if (error) *error = audioError(@"Duplicate audio cue trigger");
            return nil;
        }
        parsed.push_back(std::move(c));
    }
    _players = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, id> *bytes = [NSMutableDictionary dictionary];
    NSMutableArray<NSError *> *issues = [NSMutableArray array];
    FD directory(parsed.empty() ? -1 : openMedia(chapterDir));
    NSUInteger used = 0;
    for (auto &c : parsed) {
        for (int role = 0; role < (c.introSrc.empty() ? 1 : 2); ++role) {
            @autoreleasepool {
                const bool intro = role == 1;
                NSString *src = [NSString stringWithUTF8String:intro ? c.introSrc.c_str() : c.src.c_str()];
                NSString *key = playerKey(c, intro);
                if (!bytes[src]) {
                    NSError *readError = nil;
                    NSData *data = readAudio(directory.fd, src, TotalLimit - used, &readError);
                    bytes[src] = data ?: (id)NSNull.null;
                    if (data) used += data.length;
                    else [issues addObject:readError];
                }
                if (bytes[src] == NSNull.null) { c.enabled = false; continue; }
                AVAudioPlayer *player = _players[key];
                if (!player) {
                    NSError *decodeError = nil;
                    // No worker prepare/play: either part failing disables the
                    // whole cue. Distinct role keys prevent pooled-player aliasing.
                    player = [[AVAudioPlayer alloc] initWithData:bytes[src] error:&decodeError];
                    if (!player || !std::isfinite(player.duration) || player.duration <= 0) {
                        [issues addObject:audioError(@"AVAudioPlayer cannot decode audio", src, decodeError)];
                        c.enabled = false; continue;
                    }
                    _players[key] = player;
                }
                if (intro) c.introLength = player.duration;
                else c.length = player.duration;
            }
        }
    }
    _timeline = pmnativeosaudio::Timeline(std::move(parsed));
    _diagnostics = [issues copy];
    return self;
}
- (NSArray<NSError *> *)diagnostics { return _diagnostics; }
- (NSError *)lastPlaybackError { return _lastPlaybackError; }
- (BOOL)ownsBGM { return _ownsBGM; }
- (void)setBGMOwning:(BOOL)value {
    if (_ownsBGM == value) return;
    _ownsBGM = value;
    if (_bgmOwnershipChanged) _bgmOwnershipChanged(value);
}
- (void)installObservers {
    if (_observers || _timeline.stopped()) return;
    _observers = [NSMutableArray array];
    _background = applicationInactive();
    __weak PMNativeOSAudio *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [_observers addObject:[center addObserverForName:applicationResignNotification() object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        PMNativeOSAudio *s = weakSelf;
        if (!s) return;
        s->_background = YES; [s reconcile];
    }]];
    [_observers addObject:[center addObserverForName:applicationActiveNotification() object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        PMNativeOSAudio *s = weakSelf;
        if (!s) return;
        s->_background = NO; [s reconcile];
    }]];
    [_observers addObject:[center addObserverForName:interruptionNotification() object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        PMNativeOSAudio *s = weakSelf;
        if (!s) return;
        if ([note.userInfo[interruptionTypeKey()] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan)
            s->_interrupted = YES;
        else {
            s->_interrupted = NO;
            s->_resumeBlocked = ([note.userInfo[interruptionOptionKey()] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) == 0;
        }
        [s reconcile];
    }]];
}
- (void)samplePlaybackPositions {
    for (int ch = 0; ch < 2; ++ch) if (_playing[ch]) {
        NativePlayer body{_playing[ch]}, intro{_introPlaying[ch]};
        double cursor = _transports[ch].sample(body, intro, _timeline.paused());
        _timeline.syncPlaybackPosition(ch, _serials[ch], cursor);
    }
}
- (void)clearChannel:(int)ch {
    NativePlayer body{_playing[ch]}, intro{_introPlaying[ch]};
    _transports[ch].stop(body, intro);
    _playing[ch] = nil; _introPlaying[ch] = nil; _serials[ch] = 0;
    if (ch == 0) [self setBGMOwning:NO];
}
- (void)reconcile {
    _timeline.setSuspended(_explicitSuspended || _background || _interrupted || _resumeBlocked);
    for (int ch = 0; ch < 2; ++ch) {
        const auto slot = _timeline.slot(ch);
        if (slot.cue < 0) { [self clearChannel:ch]; continue; }
        const auto &cue = _timeline.cues()[slot.cue];
        if (_serials[ch] != slot.serial) {
            NativePlayer oldBody{_playing[ch]}, oldIntro{_introPlaying[ch]};
            _transports[ch].stop(oldBody, oldIntro); // Cancel old schedules first.
            _playing[ch] = _players[playerKey(cue)];
            _introPlaying[ch] = cue.introSrc.empty() ? nil : _players[playerKey(cue, true)];
            _serials[ch] = slot.serial;
            _transports[ch].configure(cue, _timeline.position(ch));
        }
        NativePlayer body{_playing[ch]}, intro{_introPlaying[ch]};
        _playing[ch].volume = _introPlaying[ch].volume = static_cast<float>(cue.volume);
        body.loops(cue.loop); intro.loops(false); _transports[ch].setLooping(cue.loop);
        if (_timeline.paused()) {
            _transports[ch].suspend(body, intro);
            continue;
        }
        if (!_transports[ch].running()) {
            if (ch == 0) [self setBGMOwning:YES];
            if (!_transports[ch].resume(body, intro)) {
                _lastPlaybackError = audioError(@"AVAudioPlayer failed to prepare, schedule or play OS audio", [NSString stringWithUTF8String:cue.src.c_str()]);
                _timeline.finish(ch, slot.serial); [self clearChannel:ch];
            }
        } else {
            _transports[ch].sample(body, intro);
            if (!_transports[ch].healthy(body, intro)) {
                if (cue.loop) _lastPlaybackError = audioError(@"OS audio transport stopped unexpectedly", [NSString stringWithUTF8String:cue.src.c_str()]);
                // Natural one-shot end or transport failure must not replay intro.
                _timeline.finish(ch, slot.serial); [self clearChannel:ch];
            }
        }
    }
    [self samplePlaybackPositions];
}
- (void)activateScreen:(NSInteger)screen time:(NSTimeInterval)time {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    if (screen < 0 || screen > INT_MAX || _timeline.stopped()) return;
    [self installObservers];
    // Observe a completion before considering cross-page continuity.
    if (!_timeline.paused()) for (int ch = 0; ch < 2; ++ch) if (_playing[ch]) {
        NativePlayer body{_playing[ch]}, intro{_introPlaying[ch]};
        if (!_transports[ch].healthy(body, intro)) _timeline.finish(ch, _serials[ch]);
    }
    [self samplePlaybackPositions];
    _timeline.activate(static_cast<int>(screen), time);
    [self reconcile];
}
- (void)tickAt:(NSTimeInterval)time active:(BOOL)active {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    _timeline.tick(time, active); [self reconcile];
}
- (void)tap:(uint64_t)acceptedTapID node:(NSString *)node time:(NSTimeInterval)time {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    if (node && !text(node, 63, true)) return;
    _timeline.tap(acceptedTapID, node ? node.UTF8String : "", time); [self reconcile];
}
- (void)setSuspended:(BOOL)suspended {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    _explicitSuspended = suspended;
    if (!suspended) _resumeBlocked = NO; // Explicit host resume after a denied auto-resume.
    [self reconcile];
}
- (void)setPageClockHeld:(BOOL)held {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    _timeline.setPageClockHeld(held); [self reconcile];
}
- (void)resetPlayback {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    _timeline.resetPlayback(); [self reconcile];
}
- (void)stop {
    NSAssert(NSThread.isMainThread, @"OS audio playback is main-thread-only");
    _timeline.stop(); [self reconcile];
    for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    _observers = nil; [_players removeAllObjects]; _bgmOwnershipChanged = nil;
}
- (void)dealloc {
    // The host must call stop on main before releasing its visit. No callback is
    // made during deallocation (including failed worker initializations).
    for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    for (AVAudioPlayer *player in _players.allValues) [player stop];
}
@end
