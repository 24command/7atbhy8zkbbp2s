#import "PMCoverImage.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#include "../Core/PMCoverGeometry.hpp"
static NSError*coverError(NSString*message){return [NSError errorWithDomain:@"PhiMod.Cover" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
UIImage*PMDecodeCoverData(NSData*data,NSError**error){
 CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
 if(!source){if(error)*error=coverError(@"Cannot decode cover image");return nil;}
 NSDictionary*options=@{(NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,(NSString*)kCGImageSourceShouldCacheImmediately:@YES,(NSString*)kCGImageSourceThumbnailMaxPixelSize:@2048};
 CGImageRef bitmap=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);
 if(!bitmap){if(error)*error=coverError(@"Cannot prepare cover pixels");return nil;}
 UIImage*result=[UIImage imageWithCGImage:bitmap scale:1 orientation:UIImageOrientationUp];CGImageRelease(bitmap);return result;
}
UIImage*PMCompleteCover(UIImage*image,CGFloat aspect,NSError**error){
 if(!image.CGImage||!std::isfinite(aspect)||aspect<=0){if(error)*error=coverError(@"Invalid cover aspect or image");return nil;}
 @try{
 CGSize source=CGSizeMake(CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage));
 if(image.imageOrientation==UIImageOrientationLeft||image.imageOrientation==UIImageOrientationRight||image.imageOrientation==UIImageOrientationLeftMirrored||image.imageOrientation==UIImageOrientationRightMirrored)source=CGSizeMake(source.height,source.width);
 if(source.width<=0||source.height<=0){if(error)*error=coverError(@"Cover has no pixels");return nil;}
 // Preserve small sources without forcing a huge output; cap output at 2048.
 CGFloat longest=MIN(2048,MAX(source.width,source.height));
 CGSize canvas=aspect>=1?CGSizeMake(round(longest),MAX(1,round(longest/aspect))):CGSizeMake(MAX(1,round(longest*aspect)),round(longest));
 UIGraphicsImageRendererFormat*format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
 UIGraphicsImageRenderer*renderer=[[UIGraphicsImageRenderer alloc]initWithSize:canvas format:format];
 bool sameAspect=std::fabs(source.width/source.height-aspect)<=aspect*.001;
 if(sameAspect)return [renderer imageWithActions:^(UIGraphicsImageRendererContext*c){[image drawInRect:(CGRect){CGPointZero,canvas}];}];
 // The background alone uses aspect-fill and cropping. Foreground uses aspect-fit.
 auto fill=pmcover::fit(source.width,source.height,canvas.width,canvas.height,true);
 UIImage*background=[renderer imageWithActions:^(UIGraphicsImageRendererContext*c){[[UIColor blackColor]setFill];UIRectFill((CGRect){CGPointZero,canvas});[image drawInRect:CGRectMake(fill.x,fill.y,fill.w,fill.h)];}];
 CIImage*input=[CIImage imageWithCGImage:background.CGImage];
 CIFilter*blur=[CIFilter filterWithName:@"CIGaussianBlur"];[blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];[blur setValue:@(MAX(2,longest*.025)) forKey:kCIInputRadiusKey];
 CIImage*filtered=[blur.outputImage imageByCroppingToRect:input.extent];
 static CIContext*context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];});
 CGImageRef bitmap=filtered?[context createCGImage:filtered fromRect:input.extent]:nullptr;
 if(!bitmap){if(error)*error=coverError(@"Cannot blur cover background");return nil;}
 UIImage*blurred=[UIImage imageWithCGImage:bitmap];CGImageRelease(bitmap);
 auto fit=pmcover::fit(source.width,source.height,canvas.width,canvas.height,false);
 return [renderer imageWithActions:^(UIGraphicsImageRendererContext*c){[blurred drawInRect:(CGRect){CGPointZero,canvas}];[image drawInRect:CGRectMake(fit.x,fit.y,fit.w,fit.h)];}];
 }@catch(NSException*exception){if(error)*error=coverError(exception.reason?:@"Cover composition failed");return nil;}
}
BOOL PMNormalizeCoverFolder(NSString*folder,CGFloat aspect,NSError**error){
 for(NSString*name in @[@"image.png",@"image-before.png",@"image-after.png",@"image-special.png"]){@autoreleasepool{
  NSString*path=[folder stringByAppendingPathComponent:name];if(![NSFileManager.defaultManager fileExistsAtPath:path])continue;
  NSData*data=[NSData dataWithContentsOfFile:path options:0 error:error];if(!data)return NO;
  UIImage*image=PMDecodeCoverData(data,error);if(!image)return NO;
  double w=CGImageGetWidth(image.CGImage),h=CGImageGetHeight(image.CGImage);
  // Do not compound blur padding when a previously normalized pack is reimported.
  if(std::fabs(w/h-aspect)<=aspect*.001)continue;
  UIImage*result=PMCompleteCover(image,aspect,error);if(!result)return NO;NSData*png=UIImagePNGRepresentation(result);
  if(!png){if(error)*error=coverError(@"Cannot encode composed cover");return NO;}
  if(![png writeToFile:path options:NSDataWritingAtomic error:error])return NO;
 }}return YES;
}
