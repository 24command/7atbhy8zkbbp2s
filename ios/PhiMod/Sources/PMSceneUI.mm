#import "PMResourcePackUI.h"
#import "PMAvatarUI.h"
#import "PMOfficialUI.h"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#import "PMSceneUI.hpp"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMHookBackend.h"
#import "PMContentUI.h"
#include "PMContentRuntime.hpp"
#include "PMUnlockRuntime.hpp"
#include "PMChallengeRun.hpp"
#include "PMScoreBackup.hpp"
#include "../Core/PMSettingsTabRoute.hpp"
#include "../Core/PMUIInteraction.hpp"
#include "../Core/PMModSettingsLayout.hpp"
#include "../Core/PMBuildInfo.hpp"
#include <algorithm>
#include <array>
#include <map>
#include <vector>
#include <cstdio>
namespace sceneimpl {
using pmbridge::Runtime;using pmbridge::P;
struct V2{float x,y;};struct V3{float x,y,z;};struct Rect{float x,y,w,h;};struct Color{float r,g,b,a;};
struct Bounds{float l=1e9f,r=-1e9f,b=1e9f,t=-1e9f;float width()const{return r-l;}float height()const{return t-b;}};
struct Item{uint32_t root=0;P tr=nullptr,button=nullptr,bg=nullptr,text=nullptr,sizer=nullptr,group=nullptr;V3 offset{};float fit=1;int display=-1;};
Runtime *runtime=nullptr;uint32_t selectorRoot=0,settingRoot=0,tabRoot=0;
P mirror=nullptr,mirrorText=nullptr,mirrorTransform=nullptr,mirrorButton=nullptr,mirrorGroup=nullptr,tabButton=nullptr,tabText=nullptr;
constexpr int shortcutCount=8;
std::array<Item,shortcutCount> items{};std::map<P,int> buttons;bool built=false,layoutReady=false,modEditorOpen=false,tabFailed=false;unsigned ticks=0;
std::vector<std::pair<uint32_t,bool>> hidden,animations,mutes;
static const char *labels[]={"AutoPlay","Noise","Unified","AP / FC","HP","Full Screen","Accuracy","Early / Late"};
static NSString *keys[]={@"autoplay",@"noise",@"unified",@"challenge",@"hpEnabled",@"fullScreen",@"accuracy",@"earlyLateHints"};
static NSString *shortcutKeys[]={@"shortcutAutoPlay",@"shortcutNoise",@"shortcutUnified",@"shortcutChallenge",@"shortcutHp",@"shortcutFullScreen",@"shortcutAccuracy",@"shortcutEarlyLate"};
static_assert(sizeof(labels)/sizeof(*labels)==shortcutCount && sizeof(keys)/sizeof(*keys)==shortcutCount && sizeof(shortcutKeys)/sizeof(*shortcutKeys)==shortcutCount);
BOOL shortcutVisible(NSDictionary*s,int i){return i>=0&&i<shortcutCount&&[s[shortcutKeys[i]] boolValue];}
P target(Runtime&r,uint32_t root){return root?r.gchandle_get_target(root):nullptr;}
P go(Runtime&r,P p){return r.call(p,"get_gameObject");}
P transform(Runtime&r,P p){return r.call(p,"get_transform");}
void active(Runtime&r,P p,bool yes){r.call(p,"SetActive",{"System.Boolean"},{&yes});}
P child(Runtime&r,P tr,const char*name){P t=r.call(tr,"Find",{"System.String"},{r.string_new(name)});return t?go(r,t):nullptr;}
P first(Runtime&r,P obj,P type){P a=r.children(obj,type);return a&&r.array_length(a)?r.arrayAt(a,0):nullptr;}
void setV3(Runtime&r,P tr,const char*name,V3 value){r.call(tr,name,{"UnityEngine.Vector3"},{&value});}
void color(Runtime&r,P p,Color v){r.call(p,"set_color",{"UnityEngine.Color"},{&v});}
void emptyClick(Runtime&r,P button){P e=r.object_new(r.nested(r.type("UnityEngine.UI","Button"),"ButtonClickedEvent"));uint32_t root=r.gchandle_new(e,false);try{r.call(e,".ctor");r.call(button,"set_onClick",{"UnityEngine.UI.Button.ButtonClickedEvent"},{e});}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);}
P clone(Runtime&r,P source,P parent,uint32_t &root){bool world=false;P obj=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},{source,parent,&world});root=r.gchandle_new(obj,false);return obj;}
void dispose(Runtime&r,uint32_t&root,bool destroy){if(!root)return;P obj=target(r,root);if(destroy&&r.alive(obj))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{obj});r.gchandle_free(root);root=0;}
Bounds bounds(Runtime&r,P graphic,P parent){P corners=r.array_new(r.type("UnityEngine","Vector3"),4);uint32_t root=r.gchandle_new(corners,false);Bounds b;try{r.call(transform(r,graphic),"GetWorldCorners",{"UnityEngine.Vector3[]"},{corners});for(int i=0;i<4;++i){V3 v=r.unbox<V3>(r.arrayAt(corners,i));if(parent)v=r.unbox<V3>(r.call(parent,"InverseTransformPoint",{"UnityEngine.Vector3"},{&v}));b.l=std::min(b.l,v.x);b.r=std::max(b.r,v.x);b.b=std::min(b.b,v.y);b.t=std::max(b.t,v.y);}}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);return b;}
void rebuild(Runtime&r,P tr){r.stat(r.type("UnityEngine.UI","LayoutRebuilder"),"ForceRebuildLayoutImmediate",{"UnityEngine.RectTransform"},{tr});}
void clearSelector(Runtime&r){buttons.clear();built=layoutReady=false;for(auto &s:items){dispose(r,s.root,true);s=Item{};}dispose(r,selectorRoot,false);mirror=mirrorText=mirrorTransform=mirrorButton=mirrorGroup=nullptr;}
void makeSelector(Runtime&r,P self){
 clearSelector(r);selectorRoot=r.gchandle_new(self,false);
 try{
  mirror=r.get<P>(self,"mirrorBackground");mirrorText=r.get<P>(self,"mirrorTextDisplay");
  mirrorTransform=r.call(transform(r,mirror),"get_parent");
  P parent=r.call(mirrorTransform,"get_parent"),source=go(r,mirrorTransform);
  mirrorButton=r.component(go(r,mirror),r.type("UnityEngine.UI","Button"));
  mirrorGroup=r.component(source,r.type("UnityEngine","CanvasGroup"));
  if(!mirrorButton)throw std::runtime_error("Mirror button component missing");
  for(int i=0;i<shortcutCount;++i){auto &s=items[i];P obj=clone(r,source,parent,s.root);
   active(r,obj,false);s.tr=transform(r,obj);
   P bg=child(r,s.tr,"Button"),text=child(r,s.tr,"Text");
   if(!bg||!text)throw std::runtime_error("Mirror prefab hierarchy mismatch");
   s.button=r.component(bg,r.type("UnityEngine.UI","Button"));
   s.bg=r.component(bg,r.type("Lean.Gui","LeanPolygon"));
   s.text=r.component(text,r.type("UnityEngine.UI","Text"));
   s.sizer=r.component(obj,r.type("UnityEngine.UI","Text"));
   s.group=r.component(obj,r.type("UnityEngine","CanvasGroup"));
   if(!s.button||!s.bg||!s.text||!s.sizer)throw std::runtime_error("Mirror prefab components missing");
   emptyClick(r,s.button);r.text(s.text,labels[i]);r.text(s.sizer,labels[i]);color(r,s.sizer,{0,0,0,0});
   for(const char*name:{"Legacy","Split"})if(P c=child(r,s.tr,name))active(r,c,false);
   buttons[s.button]=i;
  }
 }catch(...){
  clearSelector(r);
  // Keep the failed owner rooted: do not clone/destroy seven objects on EVERY
  // Update after a prefab mismatch. Retry only on a fresh scene/selector.
  selectorRoot=r.gchandle_new(self,false);
  throw;
 }
 built=true;ticks=0;
}
void selectorLayout(Runtime&r){
 NSDictionary*s=[[PMSettings shared] snapshot];std::vector<int>activeIndices;for(int i=0;i<shortcutCount;++i)if(shortcutVisible(s,i))activeIndices.push_back(i);P parent=r.call(mirrorTransform,"get_parent");V3 position=r.unbox<V3>(r.call(mirrorTransform,"get_localPosition")),scale=r.unbox<V3>(r.call(mirrorTransform,"get_localScale"));Bounds b=bounds(r,mirror,parent);Rect area=r.unbox<Rect>(r.call(parent,"get_rect"));float gap=std::max(4.f,b.height()*.18f),available=area.x+area.w-b.l-gap;if(!std::isfinite(available)||available<=b.width())throw std::runtime_error("Mirror layout area invalid");std::array<float,shortcutCount>widths{};for(int i:activeIndices){auto&sItem=items[i];setV3(r,sItem.tr,"set_localScale",scale);setV3(r,sItem.tr,"set_localPosition",position);rebuild(r,sItem.tr);widths[i]=std::max(1.f,bounds(r,sItem.bg,parent).width());}if(activeIndices.empty()){layoutReady=true;return;}size_t firstCount=std::min<size_t>(3,activeIndices.size());float first=0,second=0;for(size_t k=0;k<activeIndices.size();++k)(k<firstCount?first:second)+=widths[activeIndices[k]];float fit=std::clamp(std::min((available-b.width()-gap*3)/std::max(1.f,first),(available-gap*std::max<size_t>(1,activeIndices.size()-firstCount))/std::max(1.f,second)),.1f,1.f);V3 fitted{scale.x*fit,scale.y*fit,scale.z};float edge=b.r+gap,row=b.height()+gap;for(size_t k=0;k<activeIndices.size();++k){int i=activeIndices[k];auto&sItem=items[i];if(k==firstCount)edge=b.l-row*.267949f;setV3(r,sItem.tr,"set_localScale",fitted);Bounds q=bounds(r,sItem.bg,parent);sItem.offset={edge-q.l,k<firstCount?0:-row,0};sItem.fit=fit;edge+=q.width()+gap;}layoutReady=true;}
void restore(Runtime&r,std::vector<std::pair<uint32_t,bool>>&v,const char*method){for(auto x:v){P p=target(r,x.first);try{if(r.alive(p))r.call(p,method,{"System.Boolean"},{&x.second});}catch(...){}r.gchandle_free(x.first);}v.clear();}
void stash(Runtime&r,std::vector<std::pair<uint32_t,bool>>&v,P p,const char*getter,const char*setter,bool value){if(!r.alive(p))return;bool old=r.unbox<bool>(r.call(p,getter));v.emplace_back(r.gchandle_new(p,false),old);r.call(p,setter,{"System.Boolean"},{&value});}
UIWindow *window(){for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)for(UIWindow*w in ((UIWindowScene*)scene).windows)if(w.isKeyWindow)return w;return nil;}
CGFloat panelTop=100;
void projectTab(Runtime&r){P tab=target(r,tabRoot);if(!r.alive(tab))return;P txt=tabText;if(!r.alive(txt))return;P canvas=r.call(txt,"get_canvas");if(!r.alive(canvas))return;P camera=r.call(canvas,"get_worldCamera");P corners=r.array_new(r.type("UnityEngine","Vector3"),4);uint32_t root=r.gchandle_new(corners,false);try{r.call(transform(r,tab),"GetWorldCorners",{"UnityEngine.Vector3[]"},{corners});float screenH=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_height"));CGFloat bottom=0;UIWindow*w=window();for(int i=0;i<4;++i){V3 v=r.unbox<V3>(r.arrayAt(corners,i));V2 p=r.unbox<V2>(r.stat(r.type("UnityEngine","RectTransformUtility"),"WorldToScreenPoint",{"UnityEngine.Camera","UnityEngine.Vector3"},{camera,&v}));if(screenH>0)bottom=std::max(bottom,(screenH-p.y)*w.bounds.size.height/screenH);}panelTop=std::clamp(bottom+12,CGFloat(60),w.bounds.size.height*.35);}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);}
}

// The original Unity tab remains the navigation control. Only the MOD editor
// content is native UIKit; it is NOT an always-on fixed-position menu overlay.
@interface PMModEditor : UIView <UITextFieldDelegate, UIScrollViewDelegate>
@property(nonatomic,strong) NSMutableDictionary *draft;
@property(nonatomic,strong) NSMutableDictionary<NSString*,UITextField*> *fields;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *body;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *life;
@property(nonatomic,strong) PMOfficialCategories *categories;
@property(nonatomic,assign) BOOL categoriesCollapsed;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) NSInteger category;
@property(nonatomic,assign) BOOL visuals;
@property(nonatomic,assign) BOOL saveRequested;
+ (instancetype)shared;
- (void)begin;
- (void)render;
- (void)layoutEditor;
@end
@implementation PMModEditor
+ (instancetype)shared{static PMModEditor*v;static dispatch_once_t once;dispatch_once(&once,^{v=[PMModEditor new];});return v;}
- (UILabel*)label:(NSString*)text size:(CGFloat)size{UILabel*l=[UILabel new];l.text=text;l.textColor=UIColor.whiteColor;l.font=[UIFont systemFontOfSize:size weight:UIFontWeightMedium];l.numberOfLines=0;return l;}
- (UIButton*)button:(NSString*)title action:(SEL)action{PMOfficialButton*b=[PMOfficialButton new];[b setTitle:title forState:UIControlStateNormal];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)begin{self.draft=[[[PMSettings shared] snapshot] mutableCopy];self.page=0;self.category=3;self.categoriesCollapsed=NO;self.visuals=NO;self.saveRequested=NO;self.backgroundColor=[UIColor colorWithWhite:.035 alpha:.78];self.layer.cornerRadius=0;[self layoutEditor];[self render];}
- (void)layoutEditor{UIWindow*w=sceneimpl::window();if(!w)return;if(self.superview!=w)[w addSubview:self];CGFloat margin=MAX(24,w.safeAreaInsets.left+12),top=MAX(sceneimpl::panelTop,w.safeAreaInsets.top+12);self.frame=CGRectMake(margin,top,w.bounds.size.width-margin*2,w.bounds.size.height-top-MAX(18,w.safeAreaInsets.bottom));CGFloat navHeight=self.categoriesCollapsed?0:76;self.categories.hidden=self.categoriesCollapsed;self.categories.frame=CGRectMake(22,82,self.bounds.size.width-44,navHeight);CGFloat y=94+navHeight;self.scroll.frame=CGRectMake(22,y,self.bounds.size.width-44,MAX(20,self.bounds.size.height-y-12));}
- (UIStackView*)rowInCard:(PMOfficialCard*)card{UIStackView*row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=12;row.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:row];[NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],[row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],[row.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10]]];return row;}
- (void)addToggle:(NSString*)key title:(NSString*)title{PMOfficialCard*card=[PMOfficialCard new];card.fillColor=UIColor.clearColor;UIStackView*row=[self rowInCard:card];[row addArrangedSubview:[self label:title size:16]];PMOfficialToggle*sw=[PMOfficialToggle new];sw.on=[self.draft[key] boolValue];sw.accessibilityIdentifier=key;sw.accessibilityLabel=title;[sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:sw];[self.body addArrangedSubview:card];}
- (void)addNumber:(NSString*)key title:(NSString*)title{PMOfficialCard*card=[PMOfficialCard new];card.fillColor=UIColor.clearColor;UIStackView*row=[self rowInCard:card];[row addArrangedSubview:[self label:title size:16]];UITextField*f=[UITextField new];f.borderStyle=UITextBorderStyleNone;f.backgroundColor=[UIColor colorWithWhite:1 alpha:.94];f.textColor=UIColor.blackColor;f.textAlignment=NSTextAlignmentCenter;f.text=[self.draft[key] description];f.accessibilityIdentifier=key;f.accessibilityLabel=title;f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.returnKeyType=UIReturnKeyDone;f.delegate=self;[f addTarget:f action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];[f.widthAnchor constraintEqualToConstant:114].active=YES;[f.heightAnchor constraintEqualToConstant:44].active=YES;[row addArrangedSubview:f];self.fields[key]=f;[self.body addArrangedSubview:card];}
- (void)toggle:(PMOfficialToggle*)sender{self.draft[sender.accessibilityIdentifier]=@(sender.on);}
- (UIView*)modeCard:(NSString*)title detail:(NSString*)detail key:(NSString*)key page:(NSInteger)page{PMOfficialCard*card=[PMOfficialCard new];card.fillColor=UIColor.clearColor;UIStackView*row=[self rowInCard:card];UIStackView*labels=[UIStackView new];labels.axis=UILayoutConstraintAxisVertical;labels.spacing=6;[labels addArrangedSubview:[self label:title size:16]];UILabel*caption=[self label:detail size:11];caption.textColor=[UIColor colorWithWhite:1 alpha:.65];[labels addArrangedSubview:caption];[row addArrangedSubview:labels];
 if(key){PMOfficialToggle*toggle=[PMOfficialToggle new];toggle.on=[self.draft[key]boolValue];toggle.accessibilityIdentifier=key;toggle.accessibilityLabel=title;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:toggle];}
 if(page){UIButton*arrow=[self button:@"›" action:@selector(detailPage:)];arrow.tag=page;arrow.accessibilityLabel=[@"打开" stringByAppendingString:title];[arrow.widthAnchor constraintEqualToConstant:44].active=YES;[row addArrangedSubview:arrow];}
 [card.heightAnchor constraintGreaterThanOrEqualToConstant:72].active=YES;return card;}
- (void)addCards:(NSArray<UIView*>*)cards{BOOL wide=(self.category==0||self.category==1)&&self.bounds.size.width>=820;for(NSUInteger i=0;i<cards.count;i+=wide?2:1){UIStackView*row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=14;row.distribution=UIStackViewDistributionFillEqually;[row addArrangedSubview:cards[i]];if(wide)[row addArrangedSubview:i+1<cards.count?cards[i+1]:[UIView new]];[self.body addArrangedSubview:row];}}
- (void)addChoice:(NSString*)key title:(NSString*)title{NSArray*names=[key isEqualToString:@"unified"]?@[@"关闭",@"Tap",@"Drag",@"Hold",@"Flick"]:@[@"关闭",@"AP 挑战",@"FC 挑战"];NSInteger value=[self.draft[key]integerValue];UIButton*b=[self button:[NSString stringWithFormat:@"%@  ·  %@  ›",title,names[MAX(0,MIN((NSInteger)names.count-1,value))]] action:@selector(chooseMode:)];b.accessibilityIdentifier=key;[self.body addArrangedSubview:b];}
- (void)chooseMode:(UIButton*)sender{if(![self collect])return;NSString*key=sender.accessibilityIdentifier;NSArray*names=[key isEqualToString:@"unified"]?@[@"关闭",@"全部 Tap",@"全部 Drag",@"全部 Hold",@"全部 Flick"]:@[@"关闭",@"AP：Good / Bad / Miss 自动重开",@"FC：Bad / Miss 自动重开"];UIAlertController*menu=[UIAlertController alertControllerWithTitle:[key isEqualToString:@"unified"]?@"统一键型":@"自动重开挑战" message:nil preferredStyle:UIAlertControllerStyleActionSheet];for(NSUInteger i=0;i<names.count;++i){[menu addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){self.draft[key]=@(i);[self render];}]];}[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=sender;menu.popoverPresentationController.sourceRect=sender.bounds;UIViewController*host=self.window.rootViewController;while(host.presentedViewController)host=host.presentedViewController;[host presentViewController:menu animated:YES completion:nil];}
- (BOOL)collect{[self endEditing:YES];for(NSString*key in self.fields){NSString*t=[self.fields[key].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSScanner*sc=[NSScanner scannerWithString:t];sc.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];double value;if(![sc scanDouble:&value]||!sc.isAtEnd||!std::isfinite(value)){self.status.text=[NSString stringWithFormat:@"Invalid value: %@",key];return NO;}self.draft[key]=@(value);}return YES;}
- (void)render{
 for(UIView*v in self.subviews)[v removeFromSuperview];self.fields=[NSMutableDictionary new];
 UIStackView*header=[UIStackView new];header.axis=UILayoutConstraintAxisHorizontal;header.spacing=8;header.alignment=UIStackViewAlignmentCenter;header.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:header];[NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22],[header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22],[header.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],[header.heightAnchor constraintEqualToConstant:44]]];
 UIButton*back=[self button:@"‹" action:@selector(back)];[back.widthAnchor constraintEqualToConstant:44].active=YES;[header addArrangedSubview:back];NSArray*titles=@[@"MOD",@"HP 生存规则",@"区间练习 / 播放设置",@"噪域设置",@"AutoPlay 设置"];UILabel*heading=[self label:titles[MAX(0,MIN(4,self.page))] size:18];heading.numberOfLines=1;heading.adjustsFontSizeToFitWidth=YES;heading.minimumScaleFactor=.65;[heading setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];[header addArrangedSubview:heading];
 for(NSArray*entry in @[@[@"分类",NSStringFromSelector(@selector(collapseCategories))],@[@"保存",NSStringFromSelector(@selector(save))],@[@"取消",NSStringFromSelector(@selector(cancel))]]){UIButton*b=[self button:entry[0] action:NSSelectorFromString(entry[1])];NSString*symbol=[entry[0] isEqualToString:@"分类"]?@"line.3.horizontal.decrease":[entry[0] isEqualToString:@"保存"]?@"checkmark":@"xmark";b.accessibilityLabel=entry[0];[b setTitle:nil forState:UIControlStateNormal];[b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];b.tintColor=UIColor.whiteColor;[b.widthAnchor constraintEqualToConstant:44].active=YES;[header addArrangedSubview:b];}
 self.status=[self label:@"" size:12];self.status.frame=CGRectMake(26,53,MAX(100,self.bounds.size.width-52),34);self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;self.status.textColor=[UIColor colorWithWhite:1 alpha:.65];[self addSubview:self.status];
 self.categories=[PMOfficialCategories new];self.categories.selectedSegmentIndex=self.category;self.categories.expanded=!self.categoriesCollapsed;[self.categories addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];[self addSubview:self.categories];
 self.scroll=[UIScrollView new];self.scroll.delegate=self;self.scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self addSubview:self.scroll];self.body=[UIStackView new];self.body.axis=UILayoutConstraintAxisVertical;self.body.spacing=12;self.body.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.body];[NSLayoutConstraint activateConstraints:@[[self.body.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],[self.body.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],[self.body.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],[self.body.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],[self.body.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
 if(self.page==1){
  UISegmentedControl*tabs=[[UISegmentedControl alloc]initWithItems:@[@"生命规则",@"视觉效果"]];tabs.selectedSegmentIndex=self.visuals?1:0;[tabs addTarget:self action:@selector(subtab:) forControlEvents:UIControlEventValueChanged];[self.body addArrangedSubview:tabs];
  if(!self.visuals){PMOfficialCard*preview=[PMOfficialCard new];preview.fillColor=[UIColor colorWithRed:.75 green:.08 blue:.15 alpha:1];self.life=[self label:[NSString stringWithFormat:@"%@   LIFE",self.draft[@"hpMax"]] size:34];[self rowInCard:preview].alignment=UIStackViewAlignmentCenter;UIStackView*previewRow=(UIStackView*)preview.subviews.firstObject;[previewRow addArrangedSubview:self.life];[self.body addArrangedSubview:preview];[self addToggle:@"hpEnabled" title:@"HP 生存"];
   for(NSArray*a in @[@[@"hpMax",@"最大 LIFE"],@[@"hpPerfect",@"Perfect HP 增减"],@[@"hpGood",@"Good HP 增减"],@[@"hpBad",@"Bad HP 增减"],@[@"hpMiss",@"Miss HP 增减"]])[self addNumber:a[0] title:a[1]];
  }else{[self addToggle:@"hpTopEffect" title:@"顶部 HP 效果"];[self addToggle:@"hpBackgroundEffect" title:@"背景边缘警示"];[self addNumber:@"hpRed" title:@"红色阈值 %"];[self addNumber:@"hpBlue" title:@"蓝色阈值 %"];}
 }else if(self.page==2){
  [self addToggle:@"practiceMode" title:@"启用区间练习"];[self addNumber:@"playbackRate" title:@"播放倍速 0–5×"];[self addToggle:@"noteFlowEnabled" title:@"调整音符流速"];[self addNumber:@"noteFlow" title:@"音符流速 0–5×"];[self addNumber:@"practiceStart" title:@"起点 / 秒"];[self addNumber:@"practiceEnd" title:@"终点 / 秒（-1 为曲尾）"];[self addNumber:@"practicePosition" title:@"定位位置 / 秒"];[self addToggle:@"practiceLoop" title:@"到终点循环"];[self addToggle:@"practiceCountdown" title:@"开始前倒数 3 秒"];[self addToggle:@"practiceWhiteUi" title:@"白色练习面板"];
  [self.body addArrangedSubview:[self label:@"保存后进入歌曲，使用三个手柄调整起点、终点与当前位置；支持暂停预览、循环和倍速。区间练习不保存成绩。" size:13]];
 }else if(self.page==3){
  [self addToggle:@"noise" title:@"噪域"];[self addToggle:@"clearOriginalNoise" title:@"清除原谱噪域"];[self addToggle:@"noiseVisual" title:@"显示噪域视觉"];[self addNumber:@"radius" title:@"噪域半径"];[self addNumber:@"noiseGrace" title:@"噪域容错 / ms"];[self addNumber:@"holdGrace" title:@"Hold 容错 / ms"];
 }else if(self.page==4){[self addToggle:@"autoplay" title:@"AutoPlay 自动打歌"];[self addNumber:@"holdFx" title:@"长条特效间隔 / ms"];[self.body addArrangedSubview:[self label:@"自动演示；不保存成绩、RKS 或解锁进度。" size:13]];
 }else if(self.category==0 || self.category==1){
  BOOL chapters=self.category==1;[self.body addArrangedSubview:[self label:chapters?@"章节排序与显示":@"导入、编辑与管理谱面" size:22]];
  [self.body addArrangedSubview:[self label:chapters?@"新建 / 编辑章节、封面替换、排序、隐藏与导入导出。使用原版管理页调整官方章节。":@"ZIP / PEZ / JSON / PEC / RPE；搜索、元数据编辑、多难度分组、删除与导出。文件通过 iOS 系统选择器导入。" size:14]];
  [self.body addArrangedSubview:[self button:chapters?@"打开章节管理  ›":@"打开谱库管理  ›" action:chapters?@selector(contentChapters):@selector(contentLibrary)]];
 }else if(self.category==2){[self addToggle:@"enabled" title:@"自定义判定"];[self addNumber:@"perfect" title:@"Perfect / ms"];[self addNumber:@"good" title:@"Good / ms"];[self.body addArrangedSubview:[self label:@"原版：Perfect ±80 / Good ±180 ms。自定义判定启用后不保存成绩。" size:13]];
 }else if(self.category==3){
  [self addCards:@[[self modeCard:@"AutoPlay" detail:@"自动演示 · 不保存成绩" key:@"autoplay" page:4],[self modeCard:@"噪域" detail:@"噪域范围与 Hold 容错" key:@"noise" page:3],[self modeCard:@"去噪域" detail:@"清除原谱噪域 · 不保存成绩" key:@"clearOriginalNoise" page:0],[self modeCard:@"HP 生存" detail:@"生命规则与原生 HP 特效" key:@"hpEnabled" page:1],[self modeCard:@"全屏判定" detail:@"保留时间 / 键型判定 · 不保存成绩" key:@"fullScreen" page:0],[self modeCard:@"实时 ACC" detail:@"在当前分数下方显示即时准确率，不改变计分" key:@"accuracy" page:0],[self modeCard:@"去连击分" detail:@"按全谱 note 数计算 Perfect/Good 成绩 · 不保存记录" key:@"noCombo" page:0],[self modeCard:@"区间练习" detail:@"起止、循环、倒数与暂停预览" key:@"practiceMode" page:2],[self modeCard:@"音符流速 / 播放倍速" detail:@"0–5× · 区间练习内可调整" key:@"noteFlowEnabled" page:2]]];
  [self addChoice:@"unified" title:@"统一键型"];[self addChoice:@"challenge" title:@"自动重开挑战"];
 }else{
  [self.body addArrangedSubview:[self button:@"\u81ea\u5b9a\u4e49\u5934\u50cf" action:@selector(avatarSettings)]];[self addToggle:@"mainlineUnlock" title:@"主线全解锁（官方原始条件不修改成绩）"];[self.body addArrangedSubview:[self label:@"仅解除 MainStory 章节、歌曲和难度的原版锁定；不会伪造成绩、RKS 或云存档。RPE video and global Metal shaders load automatically. Chart-only / targetRange shaders are not supported yet." size:12]];[self addToggle:@"showShortcuts" title:@"选曲页快捷模式按钮"];[self addNumber:@"opacity" title:@"浮窗透明度 0–1"];[self.body addArrangedSubview:[self button:@"复制诊断日志" action:@selector(copyDiagnostics)]];
 }
 [self layoutEditor];
}
- (void)scrollViewDidScroll:(UIScrollView*)scroll{if(scroll.dragging&&scroll.contentOffset.y < -24&&self.categoriesCollapsed){self.categoriesCollapsed=NO;self.categories.expanded=YES;[self layoutEditor];}}
- (void)collapseCategories{self.categoriesCollapsed=!self.categoriesCollapsed;self.categories.expanded=!self.categoriesCollapsed;[self layoutEditor];}
- (void)detailPage:(UIButton*)sender{if([self collect]){self.page=sender.tag;[self render];}}
- (void)avatarSettings{PMShowAvatarMenu(self);}
- (void)copyDiagnostics{UIPasteboard.generalPasteboard.string=PMDiagnosticsTail(400);self.status.text=@"诊断日志已复制，可粘贴发送。";}
- (void)contentLibrary{PMShowContent(self,NO);}
- (void)contentChapters{PMShowContent(self,YES);}
- (void)categoryChanged:(PMOfficialCategories*)sender {if(![self collect]){sender.selectedSegmentIndex=self.category;return;}self.category=sender.selectedSegmentIndex;self.categoriesCollapsed=YES;self.page=0;[self render];}
- (void)hp{if([self collect]){self.page=1;[self render];}}
- (void)back{if(self.page){if([self collect]){self.page=0;[self render];}}else [self cancel];}
- (void)subtab:(UISegmentedControl*)s{if(![self collect]){s.selectedSegmentIndex=self.visuals?1:0;return;}self.visuals=s.selectedSegmentIndex==1;[self render];}
- (void)save{if(![self collect])return;NSString*error=nil;if(![[PMSettings shared] validateSnapshot:self.draft error:&error]){self.status.text=error;return;}self.saveRequested=YES;self.status.text=@"正在应用并校验…";}
- (void)cancel{self.saveRequested=NO;self.draft=nil;self.hidden=YES;[self endEditing:YES];}
@end

#include "PMChallengeSelection.inc"
namespace pmscene {
using namespace sceneimpl;
#include "PMNativeModSettings.inc"
bool settingsTabRequest(Runtime&r,void*owner,int index){
 auto route=phimod::settingsTabRoute(owner==target(r,settingRoot),nativeTabSwitch,modEditorOpen,index);
 if(route==phimod::SettingsTabRoute::Original)return false;
 char message[160];snprintf(message,sizeof(message),"MOD tab request: target=%d active=%d route=%d",index,modEditorOpen,int(route));PMDiagnosticsWrite(message);
 if(route==phimod::SettingsTabRoute::KeepMod)return true;
 if(route==phimod::SettingsTabRoute::OpenMod){if(tabButton)press(r,tabButton);return true;}
 settingsLeave(r,"native-tab");return false;
}
void settingsLeave(Runtime&r,const char*reason){if(nativeTabSwitch)return;tabTap.reset();if(modEditorOpen)PMDiagnosticsWrite((std::string("MOD page leave reason=")+reason).c_str());restore(r,hidden,"SetActive");clearNativeSettings(r);restore(r,animations,"set_enabled");restore(r,mutes,"set_mute");modEditorOpen=false;[[PMModEditor shared] cancel];
 P owner=target(r,settingRoot);if(r.alive(owner)){P tabs=r.get<P>(owner,"tabAnimators");int index=r.get<int>(owner,"currentTab");if(tabs&&index>=0&&uintptr_t(index)<r.array_length(tabs)){P tr=transform(r,r.arrayAt(tabs,index)),slider=r.get<P>(owner,"sliderController");V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));if(slider)r.call(slider,"MoveTo",{"System.Single","System.Single"},{&pos.x,&size.x});}}
}
void selectorOff(Runtime&r){challengeSelection::clear(r);clearSelector(r);}
void selectorFrame(Runtime&r,P self){runtime=&r;if(modEditorOpen)settingsLeave(r,"selector-active");if(settingRoot){clearTabBackdrop(r);dispose(r,tabRoot,true);dispose(r,settingRoot,false);tabButton=tabText=nullptr;}
 challengeSelection::frame(r,self);
 if(target(r,selectorRoot)!=self)makeSelector(r,self);if(!built)return;
 NSDictionary*s=[[PMSettings shared] snapshot];bool visible=[s[@"showShortcuts"] boolValue]&&r.unbox<bool>(r.call(go(r,mirrorTransform),"get_activeInHierarchy"))&&!r.get<bool>(self,"exit");
 V3 position=r.unbox<V3>(r.call(mirrorTransform,"get_localPosition")),scale=r.unbox<V3>(r.call(mirrorTransform,"get_localScale"));
 // Rebuild only while visible; follow the original transform every frame so
 // scene slide/fade animations do not leave detached buttons on screen.
 if(visible&&ticks++%60==0){
  layoutReady=false;
  try{selectorLayout(r);}catch(...){
   for(auto &it:items)active(r,target(r,it.root),false);
   throw;
  }
 }
 // Never activate unpositioned clones after a layout failure: their initial
 // positions all overlap Mirror and would intercept the original control.
 visible=visible&&layoutReady;
 Color fill=r.unbox<Color>(r.call(mirror,"get_color")),fg=r.unbox<Color>(r.call(mirrorText,"get_color"));float alpha=mirrorGroup?r.unbox<float>(r.call(mirrorGroup,"get_alpha")):1;
 bool interactive=visible&&!r.get<bool>(self,"isMoving")&&r.unbox<bool>(r.call(mirrorButton,"get_interactable"))&&[[PMHookBackend status][@"ok"] boolValue];
 for(int i=0;i<shortcutCount;++i){auto &it=items[i];bool supported=shortcutVisible(s,i);active(r,target(r,it.root),visible&&supported);bool click=interactive&&supported;r.call(it.button,"set_interactable",{"System.Boolean"},{&click});if(it.group){r.call(it.group,"set_alpha",{"System.Single"},{&alpha});
   bool interact=mirrorGroup?r.unbox<bool>(r.call(mirrorGroup,"get_interactable")):true;
   bool raycasts=mirrorGroup?r.unbox<bool>(r.call(mirrorGroup,"get_blocksRaycasts")):true;
   r.call(it.group,"set_interactable",{"System.Boolean"},{&interact});r.call(it.group,"set_blocksRaycasts",{"System.Boolean"},{&raycasts});}
  V3 pos{position.x+it.offset.x,position.y+it.offset.y,position.z},size{scale.x*it.fit,scale.y*it.fit,scale.z};setV3(r,it.tr,"set_localPosition",pos);setV3(r,it.tr,"set_localScale",size);
  if(i==2){static const char*types[]={"Unified","Tap","Drag","Hold","Flick"};int type=[s[@"unified"] intValue];r.text(it.text,types[std::clamp(type,0,4)]);}
  if(i==3){static const char*types[]={"AP / FC","AP","FC"};int type=[s[@"challenge"] intValue];r.text(it.text,types[std::clamp(type,0,2)]);}
  bool on=[s[keys[i]] doubleValue]!=0;Color bg=on?Color{1,1,1,fill.a}:Color{0,0,0,fill.a};Color text=on?Color{0,0,0,fg.a}:Color{1,1,1,fg.a};if(!supported){bg.a*=.35f;text.a*=.4f;}color(r,it.bg,bg);color(r,it.text,text);
  if(i==3){int mode=[s[@"challenge"] intValue];if(it.display!=mode){r.text(it.text,mode==1?"AP":mode==2?"FC":"AP / FC");it.display=mode;}}
 }
}
// Keep hit testing separate from the cloned tab Animator's graphic tracks.
// The native third tab may have disabled/masked decorative graphics; copying
// its label alone does not guarantee a valid fourth Button raycast surface.
P makeModTabHitTarget(Runtime&r,P tab){
 P hit=r.object_new(r.type("UnityEngine","GameObject"));uint32_t root=r.gchandle_new(hit,false);
 try{
  r.call(hit,".ctor",{"System.String"},{r.string_new("PhiModTabHitTarget")});
  auto add=[&](const char*ns,const char*name){return r.call(hit,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});};
  int layer=r.unbox<int>(r.call(tab,"get_layer"));r.call(hit,"set_layer",{"System.Int32"},{&layer});
  P rect=add("UnityEngine","RectTransform");bool no=false,yes=true;
  r.call(rect,"SetParent",{"UnityEngine.Transform","System.Boolean"},{transform(r,tab),&no});
  V2 zero{0,0},one{1,1};r.call(rect,"set_anchorMin",{"UnityEngine.Vector2"},{&zero});r.call(rect,"set_anchorMax",{"UnityEngine.Vector2"},{&one});
  r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&zero});r.call(rect,"set_anchoredPosition",{"UnityEngine.Vector2"},{&zero});
  P image=add("UnityEngine.UI","Image");color(r,image,{1,1,1,0});
  r.call(image,"set_maskable",{"System.Boolean"},{&no});r.call(image,"set_raycastTarget",{"System.Boolean"},{&yes});
  P group=add("UnityEngine","CanvasGroup");r.call(group,"set_ignoreParentGroups",{"System.Boolean"},{&yes});
  P button=add("UnityEngine.UI","Button");r.call(button,"set_targetGraphic",{"UnityEngine.UI.Graphic"},{image});emptyClick(r,button);
  r.gchandle_free(root);return button;
 }catch(...){r.gchandle_free(root);throw;}
}
void reportModTabFailure(NSString*message){
 PMDiagnosticsWrite(message.UTF8String);
 UIViewController*host=window().rootViewController;while(host.presentedViewController)host=host.presentedViewController;
 UIAlertController*alert=[UIAlertController alertControllerWithTitle:@"MOD" message:message preferredStyle:UIAlertControllerStyleAlert];
 [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
 [host presentViewController:alert animated:YES completion:nil];
}
bool settingsPreviewSuspended(Runtime&r,void*self){return modEditorOpen&&target(r,settingRoot)==self&&r.get<float>(self,"leaveTime")<=0;}
void settingsFrame(Runtime&r,P self){runtime=&r;
 if(target(r,settingRoot)!=self){
  settingsLeave(r,"settings-owner-change");clearTabBackdrop(r);dispose(r,tabRoot,true);dispose(r,settingRoot,false);
  settingRoot=r.gchandle_new(self,false);tabButton=tabText=nullptr;tabFailed=false;
 }
 if(tabFailed)return;
 if(!tabRoot){
  P tabs=r.get<P>(self,"tabAnimators");if(!tabs||r.array_length(tabs)<3)return;
  try{
   P source=r.arrayAt(tabs,2),tr=transform(r,source),parent=r.call(tr,"get_parent");
   P obj=clone(r,go(r,source),parent,tabRoot);active(r,obj,false);
   P anim=r.component(obj,r.type("UnityEngine","Animator"));
   if(anim){bool yes=true;r.call(anim,"set_enabled",{"System.Boolean"},{&yes});}
   P own=transform(r,obj);
   V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));
   V2 prev=r.unbox<V2>(r.call(transform(r,r.arrayAt(tabs,1)),"get_anchoredPosition"));
   pos.x+=std::max(size.x+12,pos.x-prev.x);
   r.call(own,"set_anchoredPosition",{"UnityEngine.Vector2"},{&pos});
   P button=first(r,obj,r.type("UnityEngine.UI","Button"));
   P text=first(r,obj,r.type("UnityEngine.UI","Text"));
   if(!button||!text)throw std::runtime_error("Setting tab prefab mismatch");
   emptyClick(r,button);bool no=false;r.call(button,"set_enabled",{"System.Boolean"},{&no});
   button=makeModTabHitTarget(r,obj);r.text(text,"MOD");active(r,obj,true);
   P tabLayout=r.component(go(r,parent),r.klass("SettingTabController"));if(r.alive(tabLayout))r.call(tabLayout,"Refresh");
   PMDiagnosticsWrite((std::string("MOD tab input ready: ")+phimod::settingsRevision+" build="+phimod::buildRevision).c_str());
   // Publish the click target only after the entire clone is usable.
   tabButton=button;tabText=text;
  }catch(...){
   tabFailed=true;tabButton=tabText=nullptr;dispose(r,tabRoot,true);throw;
  }
 }
 // A disabled clone's CanvasGroup otherwise keeps rejecting raycasts even
 // after Button.interactable is enabled. Mirror all three group properties.
 P tabObject=target(r,tabRoot),source=r.arrayAt(r.get<P>(self,"tabAnimators"),2);
 P ownGroups=r.children(tabObject,r.type("UnityEngine","CanvasGroup"));
 P sourceGroups=r.children(go(r,source),r.type("UnityEngine","CanvasGroup"));
 for(unsigned i=0;ownGroups&&i<r.array_length(ownGroups);++i){
  P group=r.arrayAt(ownGroups,int(i));P from=sourceGroups&&i<r.array_length(sourceGroups)?r.arrayAt(sourceGroups,int(i)):nullptr;
  float alpha=1; (void)from;
  bool yes=true;r.call(group,"set_alpha",{"System.Single"},{&alpha});
  r.call(group,"set_interactable",{"System.Boolean"},{&yes});r.call(group,"set_blocksRaycasts",{"System.Boolean"},{&yes});
 }
 bool enabled=r.get<float>(self,"leaveTime")<=0;r.call(tabButton,"set_interactable",{"System.Boolean"},{&enabled});
 r.text(tabText,"MOD");
 try{extendTabBackdrop(r);}catch(const std::exception&e){tabBackdropFailed=true;PMDiagnosticsWrite((std::string("MOD tab background: ")+e.what()).c_str());}
 PMModEditor*editor=[PMModEditor shared];if(modEditorOpen&&editor.hidden&&!nativeSettingsRoot){settingsLeave(r,"missing-native-page");return;}
 if(!modEditorOpen&&pollModTabTouch(r,self)){PMDiagnosticsWrite("MOD tab touch fallback activation");press(r,tabButton);}
 if(modEditorOpen&&nativeSettingsRoot)pollNativeSettings(r);
 if(!modEditorOpen)return;
 for(auto&entry:hidden){P obj=target(r,entry.first);if(r.alive(obj)&&r.unbox<bool>(r.call(obj,"get_activeSelf"))){bool no=false;r.call(obj,"SetActive",{"System.Boolean"},{&no});}}
 if(!r.unbox<bool>(r.call(go(r,self),"get_activeInHierarchy"))||r.get<float>(self,"leaveTime")>0){settingsLeave(r,"settings-window-exit");return;}
 if(editor.saveRequested){editor.saveRequested=NO;NSDictionary*before=[[PMSettings shared] snapshot];NSDictionary*d=[editor.draft copy];NSString*validationError=nil;if(![[PMSettings shared] validateSnapshot:d error:&validationError]){editor.status.text=validationError;return;}BOOL change=[d[@"enabled"] boolValue]!=[before[@"enabled"] boolValue]||[d[@"perfect"] doubleValue]!=[before[@"perfect"] doubleValue]||[d[@"good"] doubleValue]!=[before[@"good"] doubleValue];
  if(change&&([d[@"enabled"] boolValue]||[before[@"enabled"] boolValue])){NSDictionary*out=[PMRuntime applyJudgeSettings:[d[@"enabled"] boolValue] perfectMs:[d[@"perfect"] doubleValue] goodMs:[d[@"good"] doubleValue]];if(![out[@"ok"] boolValue]){editor.status.text=out[@"message"];return;}}
  NSString*error=nil;if(![[PMSettings shared] replaceConfiguration:d error:&error]){editor.status.text=error;return;}BOOL mainlineChanged=[d[@"mainlineUnlock"] boolValue]!=[before[@"mainlineUnlock"] boolValue];if(mainlineChanged){try{pmcontent::refreshMainlineAccess(r);}catch(const std::exception&e){editor.status.text=[NSString stringWithFormat:@"Saved; mainline refresh deferred: %s",e.what()];return;}}editor.status.text=@"Saved. Gameplay modes apply on next chart; judge verified immediately.";
 }
 if(nativeAdvanced){projectTab(r);[editor layoutEditor];}
}
bool ownsButton(P button){return button&&(challengeSelection::owns(button)||buttons.count(button)||button==tabButton||nativeActions.count(button));}
bool press(Runtime&r,P button){if(challengeSelection::owns(button)){challengeSelection::press(r,button);return true;}if(pressNativeSetting(r,button))return true;auto found=buttons.find(button);if(found!=buttons.end()){int i=found->second;P owner=target(r,selectorRoot);if(!r.alive(owner)||r.get<bool>(owner,"exit")||r.get<bool>(owner,"isMoving"))return true;NSString*key=keys[i];NSInteger old=[[[PMSettings shared] value:key] integerValue];NSNumber*value=i==2?@((old+1)%5):i==3?@((old+1)%3):@(!old);NSString*error=nil;[[PMSettings shared] setValue:value forKey:key error:&error];return true;}
 if(button!=tabButton)return false;P self=target(r,settingRoot);if(!r.alive(self))return true;if(modEditorOpen)return true;
 PMDiagnosticsWrite("MOD tab click received; creating native fourth page");
 modEditorOpen=true;
 @try{try{
  makeNativeSettings(r,self);
  // makeNativeSettings owns only the original body branches; never hide the root Canvas.
  // Preview mute/pause is owned by makeNativeSettings and restored exactly once.
  // Native page uses Unity layout, not the optional UIKit advanced-panel anchor.
 }catch(const std::exception&e){NSString*message=[NSString stringWithFormat:@"MOD settings: %s",e.what()];settingsLeave(r,"page-create-failed");reportModTabFailure(message);}}
 @catch(NSException*e){NSString*message=[NSString stringWithFormat:@"MOD settings: %@",e.reason];settingsLeave(r,"page-create-failed");reportModTabFailure(message);}return true;
}

namespace {uint32_t recoveryRoot=0;UIAlertController*recoveryAlert=nil;}
void clearRecovery(Runtime&r){if(recoveryAlert)[recoveryAlert dismissViewControllerAnimated:NO completion:nil];recoveryAlert=nil;if(recoveryRoot){r.gchandle_free(recoveryRoot);recoveryRoot=0;}}
void resultRecovery(Runtime&r,P owner,const std::string&message){
 if(recoveryAlert)return;UIWindow*w=window();UIViewController*vc=w.rootViewController;if(!vc)return;
 while(vc.presentedViewController)vc=vc.presentedViewController;
 recoveryRoot=r.gchandle_new(owner,false);Runtime*bridge=&r;
 recoveryAlert=[UIAlertController alertControllerWithTitle:@"PhiMod result error" message:[NSString stringWithUTF8String:message.c_str()] preferredStyle:UIAlertControllerStyleAlert];
 for(NSString*title in @[@"Retry",@"Back"]){bool retry=[title isEqualToString:@"Retry"];
  [recoveryAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
   P target=recoveryRoot?bridge->gchandle_get_target(recoveryRoot):nullptr;
   try{if(bridge->alive(target)){
    // Direct navigation only; no stock reward, unlock or collection helper.
    bridge->put(target,"_isRetry",retry);
    P routine=bridge->call(target,"StartNextScene",{"System.String"},{bridge->string_new(retry?"Level":"Loading")});
    bridge->call(target,"StartCoroutine",{"System.Collections.IEnumerator"},{routine});
   }}catch(const std::exception&e){NSLog(@"[PhiMod] Recovery: %s",e.what());}
   clearRecovery(*bridge);
  }]];
 }
 [vc presentViewController:recoveryAlert animated:YES completion:nil];
}

}
