#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^PMImageCropCompletion)(UIImage * _Nullable image);
@interface PMImageCropController : UIViewController
@property(nonatomic,assign) BOOL allowsCompleteCover;
- (instancetype)initWithImage:(UIImage *)image aspect:(CGFloat)aspect completion:(PMImageCropCompletion)completion;
@end
NS_ASSUME_NONNULL_END
