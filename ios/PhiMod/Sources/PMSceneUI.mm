#import <UIKit/UIKit.h>
#import "PMSceneUI.hpp"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMHookBackend.h"
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
std::array<Item,7> items{};std::map<P,int> buttons;bool built=false,layoutReady=false,open=false,tabFailed=false;unsigned ticks=0;
std::vector<std::pair<uint32_t,bool>> hidden,animations,mutes;
static const char *labels[]={"AutoPlay","Noise","Unified","AP / FC","HP","Full Screen","Accuracy"};
static NSString *keys[]={@"autoplay",@"noise",@"unified",@"challenge",@"hpEnabled",@"fullScreen",@"noCombo"};
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
  for(int i=0;i<7;++i){auto &s=items[i];P obj=clone(r,source,parent,s.root);
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
 P parent=r.call(mirrorTransform,"get_parent");V3 position=r.unbox<V3>(r.call(mirrorTransform,"get_localPosition")),scale=r.unbox<V3>(r.call(mirrorTransform,"get_localScale"));
 Bounds b=bounds(r,mirror,parent);Rect area=r.unbox<Rect>(r.call(parent,"get_rect"));float gap=std::max(4.f,b.height()*.18f),available=area.x+area.w-b.l-gap;
 if(!std::isfinite(available)||available<=b.width())throw std::runtime_error("Mirror layout area invalid");
 std::array<float,7> widths{};for(int i=0;i<7;++i){auto&s=items[i];setV3(r,s.tr,"set_localScale",scale);setV3(r,s.tr,"set_localPosition",position);rebuild(r,s.tr);widths[i]=std::max(1.f,bounds(r,s.bg,parent).width());}
 float first=widths[0]+widths[1]+widths[2],second=widths[3]+widths[4]+widths[5]+widths[6];float fit=std::clamp(std::min((available-b.width()-gap*3)/first,(available-gap*3)/second),.1f,1.f);
 V3 fitted{scale.x*fit,scale.y*fit,scale.z};float edge=b.r+gap,row=b.height()+gap;
 for(int i=0;i<7;++i){auto&s=items[i];if(i==3)edge=b.l-row*.267949f;setV3(r,s.tr,"set_localScale",fitted);Bounds q=bounds(r,s.bg,parent);s.offset={edge-q.l,i<3?0:-row,0};s.fit=fit;edge+=q.width()+gap;}
 layoutReady=true;
}
void restore(Runtime&r,std::vector<std::pair<uint32_t,bool>>&v,const char*method){for(auto x:v){P p=target(r,x.first);try{if(r.alive(p))r.call(p,method,{"System.Boolean"},{&x.second});}catch(...){}r.gchandle_free(x.first);}v.clear();}
void stash(Runtime&r,std::vector<std::pair<uint32_t,bool>>&v,P p,const char*getter,const char*setter,bool value){if(!r.alive(p))return;bool old=r.unbox<bool>(r.call(p,getter));v.emplace_back(r.gchandle_new(p,false),old);r.call(p,setter,{"System.Boolean"},{&value});}
UIWindow *window(){for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)for(UIWindow*w in ((UIWindowScene*)scene).windows)if(w.isKeyWindow)return w;return nil;}
CGFloat panelTop=100;
void projectTab(Runtime&r){P tab=target(r,tabRoot);if(!r.alive(tab))return;P txt=tabText,canvas=r.call(txt,"get_canvas"),camera=r.call(canvas,"get_worldCamera");P corners=r.array_new(r.type("UnityEngine","Vector3"),4);uint32_t root=r.gchandle_new(corners,false);try{r.call(transform(r,tab),"GetWorldCorners",{"UnityEngine.Vector3[]"},{corners});float screenH=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_height"));CGFloat bottom=0;UIWindow*w=window();for(int i=0;i<4;++i){V3 v=r.unbox<V3>(r.arrayAt(corners,i));V2 p=r.unbox<V2>(r.stat(r.type("UnityEngine","RectTransformUtility"),"WorldToScreenPoint",{"UnityEngine.Camera","UnityEngine.Vector3"},{camera,&v}));if(screenH>0)bottom=std::max(bottom,(screenH-p.y)*w.bounds.size.height/screenH);}panelTop=std::clamp(bottom+12,CGFloat(60),w.bounds.size.height*.35);}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);}
}

// The original Unity tab remains the navigation control. Only the MOD editor
// content is native UIKit; it is NOT an always-on fixed-position menu overlay.
@interface PMModEditor : UIView <UITextFieldDelegate>
@property(nonatomic,strong) NSMutableDictionary *draft;
@property(nonatomic,strong) NSMutableDictionary<NSString*,UITextField*> *fields;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *body;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *life;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) BOOL visuals;
@property(nonatomic,assign) BOOL saveRequested;
+ (instancetype)shared;
- (void)begin;
- (void)render;
- (void)layoutEditor;
@end
@implementation PMModEditor
+ (instancetype)shared{static PMModEditor*v;static dispatch_once_t once;dispatch_once(&once,^{v=[PMModEditor new];});return v;}
- (UILabel*)label:(NSString*)text size:(CGFloat)size{UILabel*l=[UILabel new];l.text=text;l.textColor=[UIColor colorWithWhite:.12 alpha:1];l.font=[UIFont systemFontOfSize:size weight:UIFontWeightMedium];l.numberOfLines=0;return l;}
- (UIButton*)button:(NSString*)title action:(SEL)action{UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.blackColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:17];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)begin{self.draft=[[[PMSettings shared] snapshot] mutableCopy];self.draft[@"noise"]=@NO;self.draft[@"unified"]=@0;self.draft[@"clearOriginalNoise"]=@NO;self.page=0;self.visuals=NO;self.saveRequested=NO;self.backgroundColor=[UIColor colorWithWhite:.96 alpha:.97];self.layer.cornerRadius=10;[self render];}
- (void)layoutEditor{UIWindow*w=sceneimpl::window();if(!w)return;if(self.superview!=w)[w addSubview:self];CGFloat margin=MAX(24,w.safeAreaInsets.left+12),top=MAX(sceneimpl::panelTop,w.safeAreaInsets.top+12);self.frame=CGRectMake(margin,top,w.bounds.size.width-margin*2,w.bounds.size.height-top-MAX(18,w.safeAreaInsets.bottom));self.scroll.frame=CGRectMake(22,96,self.bounds.size.width-44,MAX(20,self.bounds.size.height-108));}
- (void)addToggle:(NSString*)key title:(NSString*)title{UIStackView*row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;[row addArrangedSubview:[self label:title size:16]];UISwitch*sw=[UISwitch new];sw.on=[self.draft[key] boolValue];sw.accessibilityIdentifier=key;[sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:sw];[self.body addArrangedSubview:row];}
- (void)addNumber:(NSString*)key title:(NSString*)title{UIStackView*row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=18;UILabel*l=[self label:title size:16];[row addArrangedSubview:l];UITextField*f=[UITextField new];f.borderStyle=UITextBorderStyleRoundedRect;f.backgroundColor=UIColor.whiteColor;f.text=[self.draft[key] description];f.accessibilityIdentifier=key;f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.delegate=self;[f.widthAnchor constraintEqualToConstant:130].active=YES;[row addArrangedSubview:f];self.fields[key]=f;[self.body addArrangedSubview:row];}
- (void)toggle:(UISwitch*)s{self.draft[s.accessibilityIdentifier]=@(s.on);}
- (BOOL)collect{[self endEditing:YES];for(NSString*key in self.fields){NSString*t=[self.fields[key].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSScanner*sc=[NSScanner scannerWithString:t];double value;if(![sc scanDouble:&value]||!sc.isAtEnd||!std::isfinite(value)){self.status.text=[NSString stringWithFormat:@"Invalid value: %@",key];return NO;}self.draft[key]=@(value);}return YES;}
- (void)render{for(UIView*v in self.subviews)[v removeFromSuperview];self.fields=[NSMutableDictionary new];UIStackView*header=[UIStackView new];header.axis=UILayoutConstraintAxisHorizontal;header.spacing=22;header.alignment=UIStackViewAlignmentCenter;header.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:header];[NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],[header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],[header.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],[header.heightAnchor constraintEqualToConstant:38]]];
 [header addArrangedSubview:[self button:@"\u2039" action:@selector(back)]];[header addArrangedSubview:[self label:self.page==1?@"HP \u751f\u5b58\u89c4\u5219":@"MOD" size:24]];[header addArrangedSubview:[self button:@"\u4fdd\u5b58" action:@selector(save)]];[header addArrangedSubview:[self button:@"\u53d6\u6d88" action:@selector(cancel)]];
 self.status=[self label:@"Practice only - back up saves before testing. Changes take effect next chart." size:12];self.status.frame=CGRectMake(24,52,MAX(100,self.bounds.size.width-48),38);self.status.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self addSubview:self.status];self.scroll=[UIScrollView new];self.scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self addSubview:self.scroll];self.body=[UIStackView new];self.body.axis=UILayoutConstraintAxisVertical;self.body.spacing=18;self.body.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.body];[NSLayoutConstraint activateConstraints:@[[self.body.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],[self.body.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],[self.body.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],[self.body.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],[self.body.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
 if(self.page==1){UISegmentedControl*tabs=[[UISegmentedControl alloc]initWithItems:@[@"\u751f\u547d\u89c4\u5219",@"\u89c6\u89c9\u6548\u679c"]];tabs.selectedSegmentIndex=self.visuals?1:0;[tabs addTarget:self action:@selector(subtab:) forControlEvents:UIControlEventValueChanged];[self.body addArrangedSubview:tabs];
  if(!self.visuals){UIView*hex=[UIView new];[hex.heightAnchor constraintEqualToConstant:160].active=YES;CAShapeLayer*shape=[CAShapeLayer layer];UIBezierPath*p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(90,4)];[p addLineToPoint:CGPointMake(220,4)];[p addLineToPoint:CGPointMake(260,80)];[p addLineToPoint:CGPointMake(220,156)];[p addLineToPoint:CGPointMake(90,156)];[p addLineToPoint:CGPointMake(50,80)];[p closePath];shape.path=p.CGPath;shape.fillColor=[UIColor colorWithRed:.87 green:.15 blue:.19 alpha:1].CGColor;[hex.layer addSublayer:shape];self.life=[self label:[NSString stringWithFormat:@"%@\nLIFE",self.draft[@"hpMax"]] size:34];self.life.textColor=UIColor.whiteColor;self.life.textAlignment=NSTextAlignmentCenter;self.life.frame=CGRectMake(75,25,160,110);[hex addSubview:self.life];[self.body addArrangedSubview:hex];[self addToggle:@"hpEnabled" title:@"HP \u751f\u5b58"];
   for(NSArray*a in @[@[@"hpMax",@"\u6700\u5927 LIFE"],@[@"hpPerfect",@"Perfect"],@[@"hpGood",@"Good"],@[@"hpBad",@"Bad"],@[@"hpMiss",@"Miss"]])[self addNumber:a[0] title:a[1]];
  }else{[self addToggle:@"hpTopEffect" title:@"\u9876\u90e8 HP \u6548\u679c"];[self addToggle:@"hpBackgroundEffect" title:@"\u80cc\u666f\u8fb9\u7f18\u8b66\u793a"];[self addNumber:@"hpRed" title:@"\u7ea2\u8272\u9608\u503c %"];[self addNumber:@"hpBlue" title:@"\u84dd\u8272\u9608\u503c %"];}
 }else{
  [self addToggle:@"autoplay" title:@"AutoPlay"];[self addToggle:@"fullScreen" title:@"Full Screen"];[self addToggle:@"noCombo" title:@"Accuracy"];[self addNumber:@"challenge" title:@"AP / FC: 0 Off, 1 AP, 2 FC"];
  [self.body addArrangedSubview:[self button:@"HP \u751f\u5b58\u89c4\u5219  \u203a" action:@selector(hp)]];[self addToggle:@"enabled" title:@"Custom judge"];[self addNumber:@"perfect" title:@"Perfect / ms"];[self addNumber:@"good" title:@"Good / ms"];[self addToggle:@"showShortcuts" title:@"\u9009\u66f2\u5feb\u6377\u6309\u94ae"];
  [self.body addArrangedSubview:[self label:@"Noise / Unified / No Noise / Hold tuning: unavailable in this build; no placeholder switches." size:14]];
 }
 [self layoutEditor];}
- (void)hp{if([self collect]){self.page=1;[self render];}}
- (void)back{if(self.page){if([self collect]){self.page=0;[self render];}}else [self cancel];}
- (void)subtab:(UISegmentedControl*)s{if(![self collect]){s.selectedSegmentIndex=self.visuals?1:0;return;}self.visuals=s.selectedSegmentIndex==1;[self render];}
- (void)save{if(![self collect])return;NSString*error=nil;if(![[PMSettings shared] validateSnapshot:self.draft error:&error]){self.status.text=error;return;}self.saveRequested=YES;self.status.text=@"Applying and verifying...";}
- (void)cancel{self.saveRequested=NO;self.draft=nil;self.hidden=YES;[self endEditing:YES];}
@end

namespace pmscene {
using namespace sceneimpl;
void settingsLeave(Runtime&r){restore(r,hidden,"SetActive");restore(r,animations,"set_enabled");restore(r,mutes,"set_mute");open=false;[[PMModEditor shared] cancel];
 P owner=target(r,settingRoot);if(r.alive(owner)){P tabs=r.get<P>(owner,"tabAnimators");int index=r.get<int>(owner,"currentTab");if(tabs&&index>=0&&uintptr_t(index)<r.array_length(tabs)){P tr=transform(r,r.arrayAt(tabs,index)),slider=r.get<P>(owner,"sliderController");V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));if(slider)r.call(slider,"MoveTo",{"System.Single","System.Single"},{&pos.x,&size.x});}}
}
void selectorOff(Runtime&r){clearSelector(r);}
void selectorFrame(Runtime&r,P self){runtime=&r;if(open)settingsLeave(r);if(settingRoot){dispose(r,tabRoot,true);dispose(r,settingRoot,false);tabButton=tabText=nullptr;}
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
 for(int i=0;i<7;++i){auto &it=items[i];bool supported=i!=1&&i!=2;active(r,target(r,it.root),visible);bool click=interactive&&supported;r.call(it.button,"set_interactable",{"System.Boolean"},{&click});if(it.group)r.call(it.group,"set_alpha",{"System.Single"},{&alpha});
  V3 pos{position.x+it.offset.x,position.y+it.offset.y,position.z},size{scale.x*it.fit,scale.y*it.fit,scale.z};setV3(r,it.tr,"set_localPosition",pos);setV3(r,it.tr,"set_localScale",size);
  bool on=[s[keys[i]] doubleValue]!=0;Color bg=on?Color{1,1,1,fill.a}:Color{0,0,0,fill.a};Color text=on?Color{0,0,0,fg.a}:Color{1,1,1,fg.a};if(!supported){bg.a*=.35f;text.a*=.4f;}color(r,it.bg,bg);color(r,it.text,text);
  if(i==3){int mode=[s[@"challenge"] intValue];if(it.display!=mode){r.text(it.text,mode==1?"AP":mode==2?"FC":"AP / FC");it.display=mode;}}
 }
}
void settingsFrame(Runtime&r,P self){runtime=&r;
 if(target(r,settingRoot)!=self){
  settingsLeave(r);dispose(r,tabRoot,true);dispose(r,settingRoot,false);
  settingRoot=r.gchandle_new(self,false);tabButton=tabText=nullptr;tabFailed=false;
 }
 if(tabFailed)return;
 if(!tabRoot){
  P tabs=r.get<P>(self,"tabAnimators");if(!tabs||r.array_length(tabs)<3)return;
  try{
   P source=r.arrayAt(tabs,2),tr=transform(r,source),parent=r.call(tr,"get_parent");
   P obj=clone(r,go(r,source),parent,tabRoot);active(r,obj,false);
   P anim=r.component(obj,r.type("UnityEngine","Animator"));
   if(anim){bool no=false;r.call(anim,"set_enabled",{"System.Boolean"},{&no});}
   P own=transform(r,obj);
   V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));
   V2 prev=r.unbox<V2>(r.call(transform(r,r.arrayAt(tabs,1)),"get_anchoredPosition"));
   pos.x+=std::max(size.x+12,pos.x-prev.x);
   r.call(own,"set_anchoredPosition",{"UnityEngine.Vector2"},{&pos});
   P button=first(r,obj,r.type("UnityEngine.UI","Button"));
   P text=first(r,obj,r.type("UnityEngine.UI","Text"));
   if(!button||!text)throw std::runtime_error("Setting tab prefab mismatch");
   emptyClick(r,button);r.text(text,"MOD");active(r,obj,true);
   // Publish the click target only after the entire clone is usable.
   tabButton=button;tabText=text;
  }catch(...){
   tabFailed=true;tabButton=tabText=nullptr;dispose(r,tabRoot,true);throw;
  }
 }
 r.text(tabText,"MOD");
 PMModEditor*editor=[PMModEditor shared];if(open&&editor.hidden){settingsLeave(r);return;}
 if(!open)return;
 if(!r.unbox<bool>(r.call(go(r,self),"get_activeInHierarchy"))||r.get<float>(self,"leaveTime")>0){settingsLeave(r);return;}
 if(editor.saveRequested){editor.saveRequested=NO;NSDictionary*before=[[PMSettings shared] snapshot];NSDictionary*d=[editor.draft copy];NSString*validationError=nil;if(![[PMSettings shared] validateSnapshot:d error:&validationError]){editor.status.text=validationError;return;}BOOL change=[d[@"enabled"] boolValue]!=[before[@"enabled"] boolValue]||[d[@"perfect"] doubleValue]!=[before[@"perfect"] doubleValue]||[d[@"good"] doubleValue]!=[before[@"good"] doubleValue];
  if(change&&([d[@"enabled"] boolValue]||[before[@"enabled"] boolValue])){NSDictionary*out=[PMRuntime applyJudgeSettings:[d[@"enabled"] boolValue] perfectMs:[d[@"perfect"] doubleValue] goodMs:[d[@"good"] doubleValue]];if(![out[@"ok"] boolValue]){editor.status.text=out[@"message"];return;}}
  NSString*error=nil;if(![[PMSettings shared] replaceConfiguration:d error:&error]){editor.status.text=error;return;}editor.status.text=@"Saved. Gameplay modes apply on next chart; judge verified immediately.";
 }
 projectTab(r);[editor layoutEditor];
}
bool press(Runtime&r,P button){auto found=buttons.find(button);if(found!=buttons.end()){int i=found->second;if(i==1||i==2)return true;P owner=target(r,selectorRoot);if(!r.alive(owner)||r.get<bool>(owner,"exit")||r.get<bool>(owner,"isMoving"))return true;NSString*key=keys[i];NSInteger old=[[[PMSettings shared] value:key] integerValue];NSNumber*value=i==3?@((old+1)%3):@(!old);NSString*error=nil;[[PMSettings shared] setValue:value forKey:key error:&error];return true;}
 if(button!=tabButton)return false;P self=target(r,settingRoot);if(!r.alive(self))return true;if(open)return true;
 int tab=2;r.call(self,"ChangeTab",{"System.Int32"},{&tab});open=true;
 try{P tabs=r.get<P>(self,"tabAnimators");for(unsigned i=0;i<r.array_length(tabs);++i)stash(r,animations,r.arrayAt(tabs,int(i)),"get_enabled","set_enabled",false);
  P scroll=r.get<P>(self,"scrollRect"),preview=r.get<P>(self,"previewNoteHolder");for(P p:{scroll?go(r,scroll):nullptr,r.get<P>(self,"judgeLine"),r.get<P>(self,"clickPosition"),preview?go(r,preview):nullptr})if(p)stash(r,hidden,p,"get_activeSelf","SetActive",false);
  for(const char*name:{"audioSource1","audioSource2"}){P src=r.get<P>(self,name);if(src)stash(r,mutes,r.get<P>(src,"audioSource"),"get_mute","set_mute",true);}
  P slider=r.get<P>(self,"sliderController"),tr=transform(r,target(r,tabRoot));V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));r.call(slider,"MoveTo",{"System.Single","System.Single"},{&pos.x,&size.x});
  projectTab(r);[[PMModEditor shared] begin];[PMModEditor shared].hidden=NO;
 }catch(...){settingsLeave(r);throw;}return true;
}
void hpFrame(float life,float max,bool visible){static UILabel*hud=nil;static UIView*edge=nil;UIWindow*w=window();if(!w)return;if(!hud){hud=[UILabel new];hud.textAlignment=NSTextAlignmentCenter;hud.font=[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];hud.backgroundColor=[UIColor colorWithWhite:0 alpha:.35];hud.layer.cornerRadius=8;hud.clipsToBounds=YES;edge=[UIView new];edge.userInteractionEnabled=NO;edge.layer.borderWidth=6;}
 if(hud.superview!=w){[w addSubview:edge];[w addSubview:hud];}NSDictionary*s=[[PMSettings shared] snapshot];float f=max>0?std::clamp(life/max,0.f,1.f):0;UIColor*c=f<[s[@"hpRed"] floatValue]/100.f?[UIColor colorWithRed:.9 green:.12 blue:.2 alpha:1]:f<[s[@"hpBlue"] floatValue]/100.f?[UIColor colorWithRed:.98 green:.7 blue:.2 alpha:1]:[UIColor colorWithRed:.2 green:.8 blue:1 alpha:1];hud.hidden=!visible||![s[@"hpTopEffect"] boolValue];hud.textColor=c;hud.text=[NSString stringWithFormat:@"%.0f / %.0f LIFE",life,max];hud.frame=CGRectMake(w.bounds.size.width*.5-115,MAX(10,w.safeAreaInsets.top),230,32);edge.frame=w.bounds;edge.layer.borderColor=c.CGColor;edge.alpha=f<[s[@"hpRed"] floatValue]/100.f?.6f:.15f;edge.hidden=!visible||![s[@"hpBackgroundEffect"] boolValue];}
}