#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PMOSRevealChoice) {
    PMOSRevealResume, PMOSRevealDetail, PMOSRevealStart
};

@interface PMOSRevealView : UIView
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text hasSong:(BOOL)hasSong;
- (void)focusFrom:(UIView *)source to:(UIView *)target completion:(void (^)(PMOSRevealChoice))completion;
// Teardown never dispatches a song or a continuation.
- (void)cancel;
@end
