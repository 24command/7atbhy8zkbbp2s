#import "PMStockUnlockPresenter.h"
#import "PMStockUnlockAssets.hpp"
#import <QuartzCore/QuartzCore.h>
#include <memory>

namespace {
using namespace pmstock;
// points.xy are pixel offsets; points.zw are normalized anchors in Unity's y-up rect.
CAShapeLayer *shape(CALayer *parent,const Polygon &polygon,CGRect frame,bool shadow) {
    CAShapeLayer *layer=[CAShapeLayer layer];
    layer.frame=frame;
    UIBezierPath *path=[UIBezierPath bezierPath];
    for(unsigned i=0;i<4;++i) {
        const auto &v=polygon.points[i];
        CGPoint p=CGPointMake(frame.size.width*v[2]+v[0],frame.size.height*(1-v[3])-v[1]);
        if(i==0) [path moveToPoint:p]; else [path addLineToPoint:p];
    }
    [path closePath];
    layer.path=path.CGPath;
    const auto &c=polygon.rgba;
    layer.fillColor=[UIColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:c[3]].CGColor;
    // TrueShadow is a Unity component. Core Animation renders its visual equivalent.
    if(shadow) {
        layer.shadowPath=path.CGPath;
        layer.shadowOffset=CGSizeMake(0,8);
        layer.shadowRadius=16;
        layer.shadowOpacity=.5;
    }
    [parent addSublayer:layer];
    return layer;
}
void label(CALayer *parent,CGFontRef font,NSString *text,CGRect frame,CGFloat size,bool badge=false) {
    CATextLayer *layer=[CATextLayer layer];
    layer.font=font;
    layer.fontSize=size;
    layer.string=text;
    layer.foregroundColor=(badge ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    layer.alignmentMode=badge ? kCAAlignmentCenter : kCAAlignmentLeft;
    layer.truncationMode=kCATruncationEnd;
    // Allow the font's full ascender/descender instead of clipping at Unity's Text rect.
    frame.size.height=MAX(frame.size.height,1.5*size);
    layer.frame=frame;
    layer.contentsScale=UIScreen.mainScreen.scale;
    [parent addSublayer:layer];
}
UIColor *sampleColor(const Curves &curves,unsigned first,double time,CGFloat alpha) {
    return [UIColor colorWithRed:curves.sample(first,time) green:curves.sample(first+1,time)
                            blue:curves.sample(first+2,time) alpha:alpha];
}
}

@implementation PMStockUnlockInfoView {
    std::shared_ptr<pmstock::Assets> _assets;
    const pmstock::Layout *_layout;
    pmstock::Window _cueWindow;
    CALayer *_canvas;
    CAShapeLayer *_nameBar, *_infoBar;
}
+ (NSString *)stockMovieReferenceForChapter:(NSInteger)chapter {
    const auto *s=pmstock::layout(chapter);
    return s && s->movie ? @(s->movie) : nil;
}
+ (void)prepareChapter:(NSInteger)chapter songID:(NSString *)songID fields:(NSDictionary *)fields
       infoShowSeconds:(double)show infoHideSeconds:(double)hide
            completion:(void (^)(PMStockUnlockInfoView *))completion {
    const auto *s=pmstock::layout(chapter);
    pmstock::Window window{show,hide};
    NSBundle *bundle=NSBundle.mainBundle;
    NSString *selected=[songID copy];
    NSMutableDictionary *snapshot=[NSMutableDictionary new];
    for (NSString *key in @[@"title",@"artist",@"difficulty",@"level",@"charter",@"illustrator"]) {
        id value=fields[key];
        if ([value isKindOfClass:NSString.class]) snapshot[key]=[value copy];
    }
    if (!s || !window.resolve(*s) || !selected.length || ![snapshot[@"title"] length] ||
        ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"4.0.4"] ||
        ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"3"]) {
        dispatch_async(dispatch_get_main_queue(),^{ completion(nil); });
        return;
    }
    NSString *dir=[bundle.bundlePath stringByAppendingPathComponent:@"Data"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
        auto assets=std::make_shared<pmstock::Assets>();
        bool loaded=assets->load(*s,dir);
        dispatch_async(dispatch_get_main_queue(),^{
            if (!loaded) { completion(nil); return; }
            PMStockUnlockInfoView *view=[[PMStockUnlockInfoView alloc] initWithFrame:CGRectZero];
            view->_layout=s;
            view->_cueWindow=window;
            view->_assets=assets;
            view->_songID=selected;
            [view buildPanel:snapshot];
            completion(view);
        });
    }});
}
- (void)buildPanel:(NSDictionary *)fields {
    self.opaque=NO;
    self.backgroundColor=UIColor.clearColor;
    self.userInteractionEnabled=NO;
    self.clipsToBounds=YES;
    self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.accessibilityLabel=fields[@"title"];
    _canvas=[CALayer layer];
    _canvas.anchorPoint=CGPointZero;
    _canvas.bounds=CGRectMake(0,0,1920,1080);
    _canvas.hidden=YES;
    [self.layer addSublayer:_canvas];
    const auto &p=_assets->shapes;
    _infoBar=shape(_canvas,p[0],CGRectMake(0,277.5,492.5,170),true);
    shape(_infoBar,p[1],CGRectMake(486,0,6.5,170),false);
    _nameBar=shape(_canvas,p[2],CGRectMake(0,132.5,727.5,145),true);
    auto badge=shape(_nameBar,p[3],CGRectMake(517.5,-6.25,195,157.5),true);
    auto font=_assets->font;
    label(_infoBar,font,@"Chart",CGRectMake(42.5,20,420,20),20);
    label(_infoBar,font,fields[@"charter"],CGRectMake(42.5,45,_layout->chapter==0 ? 400 : 420,28),28);
    label(_infoBar,font,@"Illustration",CGRectMake(42.5,90,400,20),20);
    label(_infoBar,font,fields[@"illustrator"],CGRectMake(42.5,115,400,28),28);
    label(_nameBar,font,fields[@"title"],CGRectMake(40,20,450,60),56);
    label(_nameBar,font,fields[@"artist"],CGRectMake(40,87.5,450,30),29);
    label(badge,font,fields[@"level"],CGRectMake(0,15.25,195,100),72,true);
    label(badge,font,fields[@"difficulty"],CGRectMake(0,93,195,45),28,true);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // CanvasScaler: ScaleWithScreenSize, Expand, reference resolution 1920 x 1080.
    CGFloat scale=MIN(self.bounds.size.width/1920.,self.bounds.size.height/1080.);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _canvas.position=self.bounds.origin;
    _canvas.affineTransform=CGAffineTransformMakeScale(scale,scale);
    [CATransaction commit];
}
- (void)setPresentationSeconds:(double)seconds {
    if (!_layout) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _canvas.hidden=!std::isfinite(seconds) || seconds<_cueWindow.show || seconds>=_cueWindow.hide;
    if (!_canvas.hidden) {
        double t=_cueWindow.clipTime(*_layout,seconds);
        const auto &curves=_assets->curves;
        _canvas.opacity=curves.sample(2,t);
        _nameBar.affineTransform=CGAffineTransformMakeTranslation(curves.sample(0,t),0);
        _infoBar.affineTransform=CGAffineTransformMakeTranslation(curves.sample(1,t),0);
        if (_layout->lanes==10) {
            _infoBar.fillColor=sampleColor(curves,3,t,curves.sample(6,t)).CGColor;
            _nameBar.fillColor=sampleColor(curves,7,t,_assets->shapes[2].rgba[3]).CGColor;
        }
    }
    [CATransaction commit];
}
@end
