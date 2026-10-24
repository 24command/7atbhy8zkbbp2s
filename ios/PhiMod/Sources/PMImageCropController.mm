#import "PMImageCropController.h"
#import <QuartzCore/QuartzCore.h>
#include <cmath>

@interface PMImageCropController () <UIScrollViewDelegate>
@property(nonatomic,strong) UIImage *sourceImage;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) UIView *cropBorder;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic,copy) PMImageCropCompletion completion;
@property(nonatomic,assign) CGFloat aspect;
@property(nonatomic,assign) BOOL didLayoutImage;
@end

@implementation PMImageCropController
- (instancetype)initWithImage:(UIImage *)image aspect:(CGFloat)aspect completion:(PMImageCropCompletion)completion {
 if((self=[super initWithNibName:nil bundle:nil])){_aspect=isfinite(aspect)&&aspect>.1?aspect:(16.0/9.0);_completion=[completion copy];if(image.CGImage){CGSize px=CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage));UIGraphicsImageRendererFormat*f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;UIGraphicsImageRenderer*r=[[UIGraphicsImageRenderer alloc]initWithSize:px format:f];_sourceImage=[r imageWithActions:^(UIGraphicsImageRendererContext*c){[image drawInRect:CGRectMake(0,0,px.width,px.height)];}];}else _sourceImage=image;}
 return self;
}
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithRed:.025 green:.035 blue:.05 alpha:1];self.title=@"裁剪 / 旋转封面";
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
 UIBarButtonItem*save=[[UIBarButtonItem alloc]initWithTitle:@"使用封面" style:UIBarButtonItemStyleDone target:self action:@selector(save)];UIBarButtonItem*rotate=[[UIBarButtonItem alloc]initWithTitle:@"旋转 90°" style:UIBarButtonItemStylePlain target:self action:@selector(rotate)];self.navigationItem.rightBarButtonItems=@[save,rotate];
 self.scroll=[UIScrollView new];self.scroll.delegate=self;self.scroll.backgroundColor=UIColor.blackColor;self.scroll.clipsToBounds=YES;self.scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;self.scroll.minimumZoomScale=.01;self.scroll.maximumZoomScale=8;self.scroll.bouncesZoom=YES;self.scroll.showsHorizontalScrollIndicator=NO;self.scroll.showsVerticalScrollIndicator=NO;[self.view addSubview:self.scroll];
 self.imageView=[[UIImageView alloc]initWithImage:self.sourceImage];self.imageView.contentMode=UIViewContentModeScaleToFill;self.imageView.userInteractionEnabled=YES;[self.scroll addSubview:self.imageView];
 self.cropBorder=[UIView new];self.cropBorder.userInteractionEnabled=NO;self.cropBorder.layer.borderColor=[UIColor colorWithRed:.35 green:.9 blue:.8 alpha:1].CGColor;self.cropBorder.layer.borderWidth=2;self.cropBorder.layer.shadowColor=UIColor.blackColor.CGColor;self.cropBorder.layer.shadowOpacity=.55;self.cropBorder.layer.shadowRadius=6;[self.view addSubview:self.cropBorder];
 self.hint=[UILabel new];self.hint.text=@"双指缩放、拖动调整裁剪范围";self.hint.textColor=[UIColor colorWithWhite:1 alpha:.82];self.hint.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];self.hint.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.hint];
}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];CGFloat safeTop=self.view.safeAreaInsets.top,safeBottom=self.view.safeAreaInsets.bottom,w=MAX(1,self.view.bounds.size.width-36),h=MAX(1,self.view.bounds.size.height-safeTop-safeBottom-112);CGFloat cw=MIN(w,h*self.aspect),ch=cw/self.aspect;CGRect crop=CGRectMake((self.view.bounds.size.width-cw)/2,safeTop+18+(h-ch)/2,cw,ch);self.scroll.frame=crop;self.cropBorder.frame=crop;self.hint.frame=CGRectMake(18,CGRectGetMaxY(crop)+18,self.view.bounds.size.width-36,32);
 if(!self.didLayoutImage&&self.scroll.bounds.size.width>1&&self.sourceImage.size.width>0){self.didLayoutImage=YES;CGSize size=self.sourceImage.size;self.imageView.frame=(CGRect){CGPointZero,size};self.scroll.contentSize=size;CGFloat fit=MAX(cw/size.width,ch/size.height);self.scroll.minimumZoomScale=fit;self.scroll.maximumZoomScale=MAX(fit*6,fit+.01);self.scroll.zoomScale=fit;self.scroll.contentSize=CGSizeMake(size.width*fit,size.height*fit);[self centerImage];}
}
- (UIView*)viewForZoomingInScrollView:(UIScrollView*)scrollView{return self.imageView;}
- (void)scrollViewDidZoom:(UIScrollView*)scrollView{[self centerImage];}
- (void)centerImage {CGSize bounds=self.scroll.bounds,content=self.scroll.contentSize;CGFloat x=MAX(0,(bounds.width-content.width)/2),y=MAX(0,(bounds.height-content.height)/2);self.imageView.center=CGPointMake(content.width/2+x,content.height/2+y);}
- (void)rotate {
 UIImage*source=self.sourceImage;CGSize old=source.size,new=CGSizeMake(old.height,old.width);UIGraphicsImageRendererFormat*f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;UIGraphicsImageRenderer*r=[[UIGraphicsImageRenderer alloc]initWithSize:new format:f];UIImage*rotated=[r imageWithActions:^(UIGraphicsImageRendererContext*c){CGContextRef ctx=c.CGContext;CGContextTranslateCTM(ctx,new.width/2,new.height/2);CGContextRotateCTM(ctx,(CGFloat)M_PI_2);[source drawInRect:CGRectMake(-old.width/2,-old.height/2,old.width,old.height)];}];self.sourceImage=rotated;self.imageView.image=rotated;self.didLayoutImage=NO;self.scroll.zoomScale=1;self.scroll.contentOffset=CGPointZero;[self.view setNeedsLayout];[self.view layoutIfNeeded];}
- (UIImage*)croppedImage {
 CGFloat scale=self.scroll.zoomScale;if(scale<=0||!self.sourceImage.CGImage)return nil;CGRect rect=[self.cropBorder convertRect:self.cropBorder.bounds toView:self.imageView];rect=CGRectIntersection(CGRectIntegral(rect),CGRectMake(0,0,CGImageGetWidth(self.sourceImage.CGImage),CGImageGetHeight(self.sourceImage.CGImage)));CGImageRef image=CGImageCreateWithImageInRect(self.sourceImage.CGImage,rect);if(!image)return nil;UIImage*out=[UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];CGImageRelease(image);return out;
}
- (void)finish:(UIImage*)image {[self dismissViewControllerAnimated:YES completion:^{if(self.completion)self.completion(image);self.completion=nil;}];}
- (void)save {UIImage*image=[self croppedImage];if(!image){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"裁剪失败" message:@"裁剪区域无有效像素。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}[self finish:image];}
- (void)cancel {[self finish:nil];}
@end
