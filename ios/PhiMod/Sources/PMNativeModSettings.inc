// Native prefab controls in an independent rectangular scroll layout.
// The original settings Canvas, navigation and three page arrays stay intact.
namespace {
uint32_t nativeSettingsRoot=0;P nativeSettingsManager=nullptr;bool nativeAdvanced=false;
struct NativeOption{P item;NSString*key;float last;bool slider;};std::vector<NativeOption>nativeOptions;std::map<P,int>nativeActions;
struct NativeRow{P item;int kind;};std::vector<NativeRow>nativeRows;
P nativeScroll=nullptr,nativeViewport=nullptr,nativeContent=nullptr,nativeHolder=nullptr;
std::vector<std::pair<uint32_t,bool>>nativeBodies,nativeHeaderAnimations,nativePreviewObjects,nativePreviewMute;
struct NativeHeaderLabel{uint32_t root;Color color;bool selected;};std::vector<NativeHeaderLabel>nativeHeaderLabels;
phimod::UITapGate tabTap;P tabTouchOwner=nullptr;int nativeStableFrames=0;
bool nativeTabSwitch=false;int nativePreviousTab=0,nativeTabIndex=-1;
V2 nativeLayoutSize{},nativeHeaderPosition{},nativeHeaderSize{};bool nativeHeaderPlaced=false;
struct ModTabTouch{int finger;V2 position,raw,delta;float dt;int taps,phase,type;float pressure,maxPressure,radius,radiusVariance,altitude,azimuth;};
static_assert(sizeof(ModTabTouch)==68,"Unity Touch payload");
bool modTabContains(Runtime&r,V2 screen){
 P graphic=r.call(tabButton,"get_targetGraphic");if(!r.alive(graphic))return false;
 P canvas=r.call(graphic,"get_canvas");if(!r.alive(canvas))return false;
 P camera=nullptr;if(r.enumValue(r.call(canvas,"get_renderMode"),"UnityEngine.RenderMode")!=0)camera=r.call(canvas,"get_worldCamera");
 P rect=r.call(graphic,"get_rectTransform");
 return r.unbox<bool>(r.stat(r.type("UnityEngine","RectTransformUtility"),"RectangleContainsScreenPoint",{"UnityEngine.RectTransform","UnityEngine.Vector2","UnityEngine.Camera"},{rect,&screen,camera}));
}
bool modTabPopupShowing(Runtime&r){
 P dialogs=r.stat(r.type("UnityEngine","Object"),"FindObjectsOfType",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("Phigros.UI","MsgBox")))});
 for(uintptr_t i=0;dialogs&&i<r.array_length(dialogs);++i){P popup=r.arrayAt(dialogs,int(i));if(r.alive(popup)&&r.get<bool>(popup,"isShowing"))return true;}return false;
}
bool pollModTabTouch(Runtime&r,P self){
 if(modEditorOpen||!r.alive(tabButton)||self!=target(r,settingRoot)||r.get<float>(self,"leaveTime")>0){tabTap.reset();return false;}
 if(!r.unbox<bool>(r.call(tabButton,"IsActive"))||!r.unbox<bool>(r.call(tabButton,"IsInteractable"))){tabTap.reset();return false;}
 P input=r.type("UnityEngine","Input");if(r.unbox<int>(r.stat(input,"get_touchCount"))!=1){tabTap.reset();return false;}
 int zero=0;auto touch=r.unbox<ModTabTouch>(r.stat(input,"GetTouch",{"System.Int32"},{&zero}));
 float width=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_width")),slop=std::clamp(width*.012f,12.f,32.f);
 if(touch.phase==0){if(modTabContains(r,touch.position)&&!modTabPopupShowing(r)){tabTap.begin(touch.finger,touch.position.x,touch.position.y);tabTouchOwner=self;PMDiagnosticsWrite("MOD tab touch began inside target");}else tabTap.reset();}
 else if(touch.phase==4)tabTap.reset();
 else if(touch.phase==3){bool inside=tabTouchOwner==self&&modTabContains(r,touch.position);return tabTap.finish(touch.finger,touch.position.x,touch.position.y,slop,inside)&&!modTabPopupShowing(r);}
 else tabTap.move(touch.finger,touch.position.x,touch.position.y,slop);
 return false;
}
uint32_t tabBackdropRoot=0;V2 tabBackdropSize{},tabBackdropPosition{};bool tabBackdropFailed=false;
void clearTabBackdrop(Runtime&r){
 if(tabBackdropRoot){r.gchandle_free(tabBackdropRoot);tabBackdropRoot=0;}tabBackdropFailed=false;
}
void extendTabBackdrop(Runtime&r){
 if(tabBackdropFailed)return;
 if(!tabBackdropRoot){
  P node=transform(r,target(r,tabRoot)),layout=nullptr;
  for(int depth=0;node&&depth<32;++depth,node=r.call(node,"get_parent")){layout=r.component(go(r,node),r.klass("SettingTabController"));if(r.alive(layout))break;}
  if(!r.alive(layout)){tabBackdropFailed=true;PMDiagnosticsWrite("MOD tab background: controller not found");return;}
  P background=r.get<P>(layout,"background"),rect=r.call(background,"get_rectTransform");
  // Native Refresh sizes only its three stock titles. Extend its SAME polygon,
  // preserving its left edge, slope, color and sibling order (no input overlay).
  auto area=r.unbox<sceneimpl::Rect>(r.call(rect,"get_rect"));auto tab=bounds(r,target(r,tabRoot),rect);
  float extra=std::max(0.f,tab.r+std::fabs(area.h)*.27f+12.f-(area.x+area.w));
  V2 pivot=r.unbox<V2>(r.call(rect,"get_pivot"));tabBackdropSize=r.unbox<V2>(r.call(rect,"get_sizeDelta"));tabBackdropPosition=r.unbox<V2>(r.call(rect,"get_anchoredPosition"));
  tabBackdropSize.x+=extra;tabBackdropPosition.x+=extra*pivot.x;
  tabBackdropRoot=r.gchandle_new(rect,false);
 }
 P rect=target(r,tabBackdropRoot);if(!r.alive(rect)){clearTabBackdrop(r);return;}
 V2 size=r.unbox<V2>(r.call(rect,"get_sizeDelta")),position=r.unbox<V2>(r.call(rect,"get_anchoredPosition"));
 if(std::fabs(size.x-tabBackdropSize.x)>.1f)r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&tabBackdropSize});
 if(std::fabs(position.x-tabBackdropPosition.x)>.1f)r.call(rect,"set_anchoredPosition",{"UnityEngine.Vector2"},{&tabBackdropPosition});
}

void changeNativeTab(Runtime&r,P setting,int index){nativeTabSwitch=true;@try{r.call(setting,"ChangeTab",{"System.Int32"},{&index});}@finally{nativeTabSwitch=false;}}
bool sameNativeTransform(Runtime&r,P a,P b){return a==b||(a&&b&&r.unbox<bool>(r.stat(r.type("UnityEngine","Object"),"op_Equality",{"UnityEngine.Object","UnityEngine.Object"},{a,b})));}
P enclosingCanvas(Runtime&r,P node){for(int depth=0;node&&depth<64;++depth,node=r.call(node,"get_parent")){P c=r.component(go(r,node),r.type("UnityEngine","Canvas"));if(r.alive(c))return c;}return nullptr;}
void clearNativeSettings(Runtime&r){
 int previous=nativePreviousTab;bool wasOpen=nativeTabIndex>=0;nativeTabIndex=-1;
 nativeActions.clear();nativeOptions.clear();nativeRows.clear();nativeSettingsManager=nullptr;
 nativeScroll=nativeViewport=nativeContent=nativeHolder=nullptr;nativeAdvanced=false;nativeLayoutSize={};nativeHeaderPlaced=false;nativeStableFrames=0;tabTap.reset();
 // Remove the overlay first, then restore only the body objects we own.
 dispose(r,nativeSettingsRoot,true);restore(r,nativeBodies,"SetActive");restore(r,nativeHeaderAnimations,"set_enabled");restore(r,nativePreviewObjects,"SetActive");restore(r,nativePreviewMute,"set_mute");
 for(auto&entry:nativeHeaderLabels){P label=target(r,entry.root);try{if(r.alive(label))color(r,label,entry.color);}catch(...){}r.gchandle_free(entry.root);}nativeHeaderLabels.clear();
 P owner=target(r,settingRoot);if(wasOpen&&r.alive(owner)&&r.get<float>(owner,"leaveTime")<=0)changeNativeTab(r,owner,previous);
}
P nativeTitle(Runtime&r,NSString*text){P title=r.object_new(r.type("Phigros2.Utils.MultiLanguageText","MultiLanguageTextString"));r.call(title,".ctor");r.call(title,"set_NewString",{"System.String"},{r.managedString(text)});return title;}
P emptyListeners(Runtime&r,P method,int param){P arrayType=r.type_get_object(r.method_get_param(method,param));P element=r.call(arrayType,"GetElementType");int zero=0;return r.stat(r.type("System","Array"),"CreateInstance",{"System.Type","System.Int32"},{element,&zero});}
P nativeComponent(Runtime&r,P object,const char*ns,const char*name){return r.call(object,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});}
P nativeRectObject(Runtime&r,const char*name,P parent,bool shown=true){
 P object=r.object_new(r.type("UnityEngine","GameObject"));uint32_t handle=r.gchandle_new(object,false);
 try{r.call(object,".ctor",{"System.String"},{r.string_new(name)});active(r,object,false);P tr=nativeComponent(r,object,"UnityEngine","RectTransform");bool no=false;r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});int layer=r.unbox<int>(r.call(go(r,parent),"get_layer"));r.call(object,"set_layer",{"System.Int32"},{&layer});active(r,object,shown);}
 catch(...){r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{object});r.gchandle_free(handle);throw;}r.gchandle_free(handle);return object;
}
void nativeStretch(Runtime&r,P tr,V2 low,V2 high){
 V2 zero{0,0},center{.5f,.5f};V3 one{1,1,1},position{0,0,0};
 r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(tr,"set_pivot",{"UnityEngine.Vector2"},{&center});
 r.call(tr,"set_offsetMin",{"UnityEngine.Vector2"},{&zero});r.call(tr,"set_offsetMax",{"UnityEngine.Vector2"},{&zero});r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&one});r.call(tr,"set_localEulerAngles",{"UnityEngine.Vector3"},{&position});
}
void nativeTopRect(Runtime&r,P tr,float x,float y,float widthDelta,float height){
 V2 lo{0,1},hi{1,1},pivot{0,1},size{widthDelta,height},pos{x,-y};V3 one{1,1,1},zero{0,0,0};
 r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&lo});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&hi});r.call(tr,"set_pivot",{"UnityEngine.Vector2"},{&pivot});
 r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(tr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&pos});r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&one});r.call(tr,"set_localEulerAngles",{"UnityEngine.Vector3"},{&zero});
}
void positionNativeHeader(Runtime&r){
 P owner=target(r,settingRoot),tab=target(r,tabRoot);if(!r.alive(owner)||!r.alive(tab))return;
 P tr=transform(r,tab);V2 pos=r.unbox<V2>(r.call(tr,"get_anchoredPosition")),size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));
 if(!nativeHeaderPlaced||std::fabs(pos.x-nativeHeaderPosition.x)>.1f||std::fabs(size.x-nativeHeaderSize.x)>.1f){P slider=r.get<P>(owner,"sliderController");if(r.alive(slider))r.call(slider,"MoveTo",{"System.Single","System.Single"},{&pos.x,&size.x});nativeHeaderPosition=pos;nativeHeaderSize=size;nativeHeaderPlaced=true;}
 // Keep the native tab animations alive; only the selected caption tint differs.
 for(auto&entry:nativeHeaderLabels){P label=target(r,entry.root);if(!r.alive(label))continue;Color c=entry.selected?Color{0,0,0,1}:Color{1,1,1,1};Color current=r.unbox<Color>(r.call(label,"get_color"));if(current.r!=c.r||current.g!=c.g||current.b!=c.b||current.a!=c.a)color(r,label,c);}
}
void layoutNativeRows(Runtime&r,bool force=false){
 P tr=nativeViewport;sceneimpl::Rect rect=r.unbox<sceneimpl::Rect>(r.call(tr,"get_rect"));
 if(!(rect.w>0&&rect.h>0))return;
 if(!force&&std::fabs(rect.w-nativeLayoutSize.x)<.5f&&std::fabs(rect.h-nativeLayoutSize.y)<.5f)return;
 float normalized=r.unbox<float>(r.call(nativeScroll,"get_verticalNormalizedPosition"));
 std::vector<float>heights;for(auto&row:nativeRows){float original=r.unbox<float>(r.call(row.item,"get_Height"));heights.push_back(std::max(row.kind==2?120.f:76.f,original));}
 auto layout=phimod::modSettingsLayout(rect.w,rect.h,heights);
 nativeTopRect(r,nativeContent,0,0,0,layout.contentHeight);nativeTopRect(r,nativeHolder,0,0,0,layout.contentHeight);
 for(size_t i=0;i<nativeRows.size();++i){auto&row=nativeRows[i];auto box=layout.rows[i];P rowRect=r.get<P>(row.item,"rectTransform");nativeTopRect(r,rowRect,box.x,box.y,-2*box.x,box.height);
  // Keep original prefab fonts/colors/control graphics. Constrain title to the
  // visible row; native RefreshPosition otherwise pushes it left with row Y.
  P title=r.get<P>(row.item,"title"),titleRect=transform(r,title);V2 lo{0,row.kind==2?.55f:0.f},hi{1,1},min{32,8},max{row.kind==1?-180.f:-32.f,-8};
  r.call(titleRect,"set_anchorMin",{"UnityEngine.Vector2"},{&lo});r.call(titleRect,"set_anchorMax",{"UnityEngine.Vector2"},{&hi});r.call(titleRect,"set_offsetMin",{"UnityEngine.Vector2"},{&min});r.call(titleRect,"set_offsetMax",{"UnityEngine.Vector2"},{&max});
  bool yes=true;int minimum=18,maximum=std::max(minimum,r.unbox<int>(r.call(title,"get_fontSize")));r.call(title,"set_resizeTextMaxSize",{"System.Int32"},{&maximum});r.call(title,"set_resizeTextForBestFit",{"System.Boolean"},{&yes});r.call(title,"set_resizeTextMinSize",{"System.Int32"},{&minimum});
 }
 r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},{});float restored=force?1.f:std::clamp(normalized,0.f,1.f);r.call(nativeScroll,"set_verticalNormalizedPosition",{"System.Single"},{&restored});nativeLayoutSize={rect.w,rect.h};
 char log[180];snprintf(log,sizeof(log),"MOD rectangular layout width=%.1f height=%.1f content=%.1f rows=%lu",rect.w,rect.h,layout.contentHeight,(unsigned long)nativeRows.size());PMDiagnosticsWrite(log);
}
void hideNativeBody(Runtime&r,P canvasTr,P node){
 // Hide a direct BODY branch, never the root Canvas or the navigation branch.
 if(!r.alive(node)||sameNativeTransform(r,node,canvasTr))throw std::runtime_error("Cannot hide settings root Canvas");
 P navigation=transform(r,target(r,tabRoot));for(P parent=r.call(navigation,"get_parent");parent&&!sameNativeTransform(r,parent,canvasTr);parent=r.call(parent,"get_parent"))navigation=parent;
 if(sameNativeTransform(r,node,navigation))throw std::runtime_error("Cannot hide settings navigation");
 for(auto&entry:nativeBodies)if(sameNativeTransform(r,transform(r,target(r,entry.first)),node))return;
 stash(r,nativeBodies,go(r,node),"get_activeSelf","SetActive",false);
}
void makeNativeSettings(Runtime&r,P setting){
 clearNativeSettings(r);P source=r.get<P>(setting,"scrollRect"),original=r.get<P>(setting,"settingItemsManager");if(!r.alive(source)||!r.alive(original))throw std::runtime_error("Native setting templates unavailable");
 P sourceCanvas=enclosingCanvas(r,transform(r,source));if(!r.alive(sourceCanvas))throw std::runtime_error("Native settings Canvas unavailable");P canvas=r.call(sourceCanvas,"get_rootCanvas"),canvasTr=transform(r,canvas);
 nativePreviousTab=std::clamp(r.get<int>(setting,"currentTab"),0,2);nativeTabIndex=3;
 try{
  P tabs=r.get<P>(setting,"tabAnimators");for(int i=0;i<3;++i){P labels=r.children(go(r,r.arrayAt(tabs,i)),r.type("UnityEngine.UI","Text"));for(uintptr_t j=0;labels&&j<r.array_length(labels);++j){P label=r.arrayAt(labels,int(j));nativeHeaderLabels.push_back({r.gchandle_new(label,false),r.unbox<Color>(r.call(label,"get_color")),false});}}
  nativeHeaderLabels.push_back({r.gchandle_new(tabText,false),r.unbox<Color>(r.call(tabText,"get_color")),true});
  // Keep native Canvas/navigation in its valid original state. MOD is an
  // independent page, not a fourth index in the three-element animator arrays.
  changeNativeTab(r,setting,0);
  for(const char*field:{"previewNoteHolder","judgeLine","clickPosition"}){P object=r.get<P>(setting,field);if(!r.alive(object))continue;P gameObject=field==std::string("previewNoteHolder")?go(r,object):object;stash(r,nativePreviewObjects,gameObject,"get_activeSelf","SetActive",false);}
  for(const char*field:{"audioSource1","audioSource2"}){P source=r.get<P>(setting,field);if(!r.alive(source))continue;P audio=r.get<P>(source,"audioSource");if(r.alive(audio))stash(r,nativePreviewMute,audio,"get_mute","set_mute",true);r.call(source,"Pause");}

  for(int i=0;i<3;++i)stash(r,nativeHeaderAnimations,r.arrayAt(tabs,i),"get_enabled","set_enabled",false);
  P ownAnimator=r.component(target(r,tabRoot),r.type("UnityEngine","Animator"));if(r.alive(ownAnimator))stash(r,nativeHeaderAnimations,ownAnimator,"get_enabled","set_enabled",false);
  P body=transform(r,source),parent=r.call(body,"get_parent");for(int depth=0;parent&&!sameNativeTransform(r,parent,canvasTr)&&depth<64;++depth){body=parent;parent=r.call(body,"get_parent");}
  if(!sameNativeTransform(r,parent,canvasTr))throw std::runtime_error("Settings body is outside Canvas");hideNativeBody(r,canvasTr,body);
  P staticBody=r.call(canvasTr,"Find",{"System.String"},{r.string_new("StaticFrameContainer")});if(r.alive(staticBody))hideNativeBody(r,canvasTr,staticBody);
  P root=nativeRectObject(r,"PhiMod Settings Page",canvasTr,false);nativeSettingsRoot=r.gchandle_new(root,false);P rootTr=transform(r,root);
  nativeStretch(r,rootTr,{.12f,.08f},{.94f,.84f});
  // Body overlay is below existing TabBar, not over its hit targets.
  int layerIndex=r.unbox<int>(r.call(body,"GetSiblingIndex"))+1;r.call(rootTr,"SetSiblingIndex",{"System.Int32"},{&layerIndex});
  nativeScroll=nativeComponent(r,root,"UnityEngine.UI","ScrollRect");
  P view=nativeRectObject(r,"Viewport",rootTr);nativeViewport=transform(r,view);nativeStretch(r,nativeViewport,{0,0},{1,1});
  P image=nativeComponent(r,view,"UnityEngine.UI","Image");color(r,image,{0,0,0,0});bool yes=true,no=false;r.call(image,"set_raycastTarget",{"System.Boolean"},{&yes});nativeComponent(r,view,"UnityEngine.UI","RectMask2D");
  nativeContent=transform(r,nativeRectObject(r,"Content",nativeViewport));nativeHolder=transform(r,nativeRectObject(r,"Items",nativeContent));
  nativeTopRect(r,nativeContent,0,0,0,1);nativeTopRect(r,nativeHolder,0,0,0,1);
  nativeSettingsManager=r.call(root,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.klass("SettingItemsManager")))});
  P viewport=nativeViewport,content=nativeContent,holder=nativeHolder;
  r.put(nativeSettingsManager,"viewport",viewport);r.put(nativeSettingsManager,"content",content);r.put(nativeSettingsManager,"itemsHolder",holder);r.put(nativeSettingsManager,"offset",0.f);
  for(const char*field:{"buttonPrefab","sliderPrefab","togglePrefab"})r.put(nativeSettingsManager,field,r.get<P>(original,field));
  r.call(nativeScroll,"set_content",{"UnityEngine.RectTransform"},{content});r.call(nativeScroll,"set_viewport",{"UnityEngine.RectTransform"},{viewport});r.call(nativeScroll,"set_horizontal",{"System.Boolean"},{&no});r.call(nativeScroll,"set_vertical",{"System.Boolean"},{&yes});int movement=2;r.call(nativeScroll,"set_movementType",{"UnityEngine.UI.ScrollRect.MovementType"},{&movement});
  P addButton=r.resolve(r.klass("SettingItemsManager"),"AddButton",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","UnityEngine.Events.UnityAction[]"});
  NSArray*titles=@[@"\u8c31\u5e93\u7ba1\u7406",@"\u7ae0\u8282\u7ba1\u7406",@"\u76ae\u80a4 / \u97f3\u6548 / \u7279\u6548",@"\u9ad8\u7ea7\u53c2\u6570\uff08\u5224\u5b9a / HP / \u7ec3\u4e60\uff09"];
  for(int action=0;action<(int)titles.count;++action){P listeners=emptyListeners(r,addButton,1);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(addButton,nativeSettingsManager,{nativeTitle(r,titles[action]),listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);P button=r.get<P>(item,"button");emptyClick(r,button);nativeActions[button]=action;nativeRows.push_back({item,0});}
  P toggle=r.resolve(r.klass("SettingItemsManager"),"AddToggle",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Boolean","UnityEngine.Events.UnityAction<System.Boolean>[]"});
  for(NSArray*entry in @[@[@"autoplay",@"AutoPlay"],@[@"noise",@"\u566a\u57df"],@[@"clearOriginalNoise",@"\u6e05\u9664\u539f\u8c31\u566a\u57df"],@[@"hpEnabled",@"HP \u751f\u5b58"],@[@"fullScreen",@"\u5168\u5c4f\u5224\u5b9a"],@[@"accuracy",@"\u5b9e\u65f6 ACC"],@[@"noCombo",@"\u53bb\u9664\u8fde\u51fb\u5206"],@[@"practiceMode",@"\u533a\u95f4\u7ec3\u4e60"],@[@"showShortcuts",@"\u9009\u66f2\u5feb\u6377\u6309\u94ae"]]){
   bool value=PMSettingBool([entry[0]UTF8String]);P listeners=emptyListeners(r,toggle,2);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(toggle,nativeSettingsManager,{nativeTitle(r,entry[1]),&value,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,entry[0],value?1.f:0.f,false});nativeRows.push_back({item,1});
  }
  P slider=r.resolve(r.klass("SettingItemsManager"),"AddSlider",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Single","System.Single","System.Single","UnityEngine.Events.UnityAction<System.Single>[]"});
  float value=[[[PMSettings shared]value:@"opacity"]floatValue],low=0,high=1;P listeners=emptyListeners(r,slider,4);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(slider,nativeSettingsManager,{nativeTitle(r,@"\u60ac\u6d6e\u7a97\u900f\u660e\u5ea6"),&value,&low,&high,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,@"opacity",value,true});nativeRows.push_back({item,2});

  active(r,root,true);r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},{});layoutNativeRows(r,true);positionNativeHeader(r);
  if(nativeRows.empty()||nativeLayoutSize.x<=0||!r.unbox<bool>(r.call(root,"get_activeInHierarchy")))throw std::runtime_error("MOD page layout is not visible");
  PMDiagnosticsWrite((std::string("MOD independent scroll page ready: ")+phimod::settingsRevision+" build="+phimod::buildRevision).c_str());
 }catch(...){clearNativeSettings(r);throw;}
}
void pollNativeSettings(Runtime&r){
 P root=target(r,nativeSettingsRoot);if(!r.alive(root))return;
 for(auto&entry:nativeBodies){P body=target(r,entry.first);if(r.alive(body)&&r.unbox<bool>(r.call(body,"get_activeSelf")))active(r,body,false);}
 positionNativeHeader(r);PMModEditor*editor=[PMModEditor shared];
 if(nativeAdvanced&&editor.hidden){nativeAdvanced=false;active(r,root,true);for(auto&option:nativeOptions){float value=[[[PMSettings shared]value:option.key]floatValue];if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&value});else{bool on=value!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}option.last=value;}}
 if(nativeAdvanced)return;layoutNativeRows(r);
 if(++nativeStableFrames==2){PMDiagnosticsWrite("MOD page stable: original navigation retained; rectangular rows; full scroll extent");}
 for(auto&option:nativeOptions){float value=option.slider?r.unbox<float>(r.call(option.item,"get_Value")):(r.unbox<bool>(r.call(option.item,"get_Value"))?1.f:0.f);if(std::fabs(value-option.last)<.0001f)continue;NSString*error=nil;if([[PMSettings shared]setValue:@(value) forKey:option.key error:&error])option.last=value;else{float old=option.last;if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&old});else{bool on=old!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}PMDiagnosticsWrite(error.UTF8String);}}
}
bool pressNativeSetting(Runtime&r,P button){auto found=nativeActions.find(button);if(found==nativeActions.end())return false;UIWindow*w=window();UIView*source=w.rootViewController.view;
 if(found->second==0)PMShowContent(source,NO);else if(found->second==1)PMShowContent(source,YES);else if(found->second==2)PMShowResourcePackPicker(source);else{nativeAdvanced=true;active(r,target(r,nativeSettingsRoot),false);[[PMModEditor shared]begin];[PMModEditor shared].hidden=NO;}
 return true;
}
}
