#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// ImageIO applies EXIF orientation; memory is bounded before bitmap decoding.
UIImage* _Nullable PMDecodeCoverData(NSData*data,NSError**error);
UIImage* _Nullable PMBlurCover(UIImage*uprightImage,CGFloat radius,NSError* _Nullable * _Nullable error);
UIImage* _Nullable PMCompleteCover(UIImage*image,CGFloat aspect,NSError**error);
BOOL PMNormalizeCoverFolder(NSString*folder,CGFloat aspect,NSError**error);
NS_ASSUME_NONNULL_END
