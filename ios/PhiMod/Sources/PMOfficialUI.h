#import <UIKit/UIKit.h>
// UIKit equivalents of Android OfficialToggleDrawable / ModCategoryBar.
// Same tan(15 degree) cut and 96:36 switch geometry; no Android ABI offsets.
@interface PMOfficialCard : UIView
@property(nonatomic,strong) UIColor *fillColor;
@end
@interface PMOfficialButton : UIButton
@property(nonatomic,assign) BOOL flatStyle;
@property(nonatomic,assign) CGFloat inverseSlope;
@end
@interface PMOfficialToggle : UIControl
@property(nonatomic,assign,getter=isOn) BOOL on;
@end
@interface PMOfficialCategories : UIControl
@property(nonatomic,assign) NSInteger selectedSegmentIndex;
@property(nonatomic,assign) BOOL expanded;
@end
