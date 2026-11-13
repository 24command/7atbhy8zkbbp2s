// Reuse the game's actual setting prefab factories and layout functions.
namespace {
uint32_t nativeSettingsRoot=0;P nativeSettingsManager=nullptr;bool nativeAdvanced=false;
struct NativeOption{P item;NSString*key;float last;bool slider;};std::vector<NativeOption>nativeOptions;std::map<P,int>nativeActions;
phimod::UITapGate tabTap;P tabTouchOwner=nullptr;int nativeStableFrames=0;
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
bool nativeTabSwitch=false;int nativePreviousTab=0,nativeTabIndex=-1;uint32_t originalFrames=0,originalTabs=0,originalContents=0;
void changeNativeTab(Runtime&r,P setting,int index){nativeTabSwitch=true;@try{r.call(setting,"ChangeTab",{"System.Int32"},{&index});}@finally{nativeTabSwitch=false;}}
void clearNativeSettings(Runtime&r){
 P setting=target(r,settingRoot);
 if(originalFrames&&r.alive(setting)){
  if(r.get<int>(setting,"currentTab")==nativeTabIndex)changeNativeTab(r,setting,nativePreviousTab);
  r.put(setting,"frameAnimators",target(r,originalFrames));r.put(setting,"tabAnimators",target(r,originalTabs));r.put(setting,"tabScrollContents",target(r,originalContents));
 }
 for(uint32_t*h:{&originalFrames,&originalTabs,&originalContents})if(*h){r.gchandle_free(*h);*h=0;}nativeTabIndex=-1;
 nativeStableFrames=0;tabTap.reset();nativeOptions.clear();nativeActions.clear();nativeSettingsManager=nullptr;nativeAdvanced=false;dispose(r,nativeSettingsRoot,true);
}
bool childPath(Runtime&r,P source,P node,std::vector<int>&path){for(int depth=0;node&&node!=source&&depth<32;++depth){path.push_back(r.unbox<int>(r.call(node,"GetSiblingIndex")));node=r.call(node,"get_parent");}return node==source;}
P mappedTransform(Runtime&r,P source,P clone,P node){std::vector<int>path;if(!childPath(r,source,node,path))throw std::runtime_error("Settings template reference lies outside its frame");for(auto i=path.rbegin();i!=path.rend();++i){int index=*i;clone=r.call(clone,"GetChild",{"System.Int32"},{&index});}return clone;}
P appendSettingArray(Runtime&r,P old,P type,P extra){int count=(int)r.array_length(old);P array=r.array_new(type,count+1);uint32_t root=r.gchandle_new(array,false);try{for(int i=0;i<=count;++i){P value=i==count?extra:r.arrayAt(old,i);r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),array,{value,&i});}}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);return array;}
void registerNativeTab(Runtime&r,P setting,P frame,P content){
 P frames=r.get<P>(setting,"frameAnimators"),tabs=r.get<P>(setting,"tabAnimators"),contents=r.get<P>(setting,"tabScrollContents");
 nativeTabIndex=(int)r.array_length(tabs);if(nativeTabIndex!=3||r.array_length(frames)!=3||r.array_length(contents)!=3)throw std::runtime_error("Unexpected native settings tab count");
 nativePreviousTab=std::clamp(r.get<int>(setting,"currentTab"),0,2);
 if(!r.alive(frame)||!r.alive(content)||!r.alive(r.component(target(r,tabRoot),r.type("UnityEngine","Animator"))))throw std::runtime_error("Fourth settings tab is missing its native animator or content");
 originalFrames=r.gchandle_new(frames,false);originalTabs=r.gchandle_new(tabs,false);originalContents=r.gchandle_new(contents,false);
 r.put(setting,"frameAnimators",appendSettingArray(r,frames,r.type("UnityEngine","Animator"),frame));
 r.put(setting,"tabAnimators",appendSettingArray(r,tabs,r.type("UnityEngine","Animator"),r.component(target(r,tabRoot),r.type("UnityEngine","Animator"))));
 r.put(setting,"tabScrollContents",appendSettingArray(r,contents,r.type("UnityEngine","Transform"),content));
}
P nativeTitle(Runtime&r,NSString*text){P title=r.object_new(r.type("Phigros2.Utils.MultiLanguageText","MultiLanguageTextString"));r.call(title,".ctor");r.call(title,"set_NewString",{"System.String"},{r.managedString(text)});return title;}
P emptyListeners(Runtime&r,P method,int param){P arrayType=r.type_get_object(r.method_get_param(method,param));P element=r.call(arrayType,"GetElementType");int zero=0;return r.stat(r.type("System","Array"),"CreateInstance",{"System.Type","System.Int32"},{element,&zero});}
void makeNativeSettings(Runtime&r,P setting){
 // Preflight the original tab/layout interfaces before touching page state.
 r.resolve(r.klass("Setting"),"ChangeTab",{"System.Int32"});
 r.field(r.klass("Setting"),"frameAnimators","UnityEngine.Animator[]",false);
 r.field(r.klass("Setting"),"tabAnimators","UnityEngine.Animator[]",false);
 r.field(r.klass("Setting"),"tabScrollContents","UnityEngine.Transform[]",false);
 for(const char*name:{"viewport","content","itemsHolder"})r.field(r.klass("SettingItemsManager"),name,"UnityEngine.RectTransform",false);
 r.resolve(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},true);
 clearNativeSettings(r);P source=r.get<P>(setting,"scrollRect"),original=r.get<P>(setting,"settingItemsManager");
 if(!r.alive(source)||!r.alive(original))throw std::runtime_error("Native setting templates unavailable");
 P frames=r.get<P>(setting,"frameAnimators"),sourceFrame=nullptr;
 for(int i=0;i<(int)r.array_length(frames);++i){P candidate=r.arrayAt(frames,i);std::vector<int>path;if(childPath(r,transform(r,candidate),transform(r,source),path)){sourceFrame=candidate;break;}}
 if(!sourceFrame)throw std::runtime_error("Settings scroll frame not found");
 P sourceTransform=transform(r,sourceFrame),parent=r.call(sourceTransform,"get_parent");
 P root=clone(r,go(r,sourceFrame),parent,nativeSettingsRoot);active(r,root,false);
 // Only the page visual/template is cloned. A copied Setting controller must
 // never run native Update or take ownership of the live settings session.
 P controllers=r.children(root,r.klass("Setting"));bool disabled=false;
 for(uintptr_t i=0;controllers&&i<r.array_length(controllers);++i)r.call(r.arrayAt(controllers,int(i)),"set_enabled",{"System.Boolean"},{&disabled});
 try{
  P cloneTransform=transform(r,root);
  P scrollTransform=mappedTransform(r,sourceTransform,cloneTransform,transform(r,source));
  P scroll=r.component(go(r,scrollTransform),r.type("UnityEngine.UI","ScrollRect"));
  P content=mappedTransform(r,sourceTransform,cloneTransform,r.get<P>(original,"content"));
  P viewport=mappedTransform(r,sourceTransform,cloneTransform,r.get<P>(original,"viewport"));
  P holder=mappedTransform(r,sourceTransform,cloneTransform,r.get<P>(original,"itemsHolder"));
  if(content==holder||viewport==holder)throw std::runtime_error("Native settings hierarchy must keep content and itemsHolder separate");
  // Hide gameplay-only decorations copied with the frame, not its viewport.
  for(const char*field:{"previewNoteHolder","judgeLine","clickPosition"}){P object=r.get<P>(setting,field);if(!r.alive(object))continue;std::vector<int>path;P node=transform(r,object);if(childPath(r,sourceTransform,node,path)){P mapped=mappedTransform(r,sourceTransform,cloneTransform,node);active(r,go(r,mapped),false);}}
  for(int i=r.unbox<int>(r.call(holder,"get_childCount"))-1;i>=0;--i){P child=r.call(holder,"GetChild",{"System.Int32"},{&i});bool world=false;active(r,go(r,child),false);r.call(child,"SetParent",{"UnityEngine.Transform","System.Boolean"},{nullptr,&world});r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go(r,child)});}
  nativeSettingsManager=first(r,root,r.klass("SettingItemsManager"));if(!nativeSettingsManager)nativeSettingsManager=r.call(root,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.klass("SettingItemsManager")))});
  r.put(nativeSettingsManager,"viewport",viewport);r.put(nativeSettingsManager,"content",content);r.put(nativeSettingsManager,"itemsHolder",holder);r.put(nativeSettingsManager,"offset",0.f);
  for(const char*field:{"buttonPrefab","sliderPrefab","togglePrefab"})r.put(nativeSettingsManager,field,r.get<P>(original,field));
  r.call(scroll,"set_content",{"UnityEngine.RectTransform"},{content});r.call(scroll,"set_viewport",{"UnityEngine.RectTransform"},{viewport});
  // Do not keep source-page callbacks pointing at the original manager.
  P changed=r.object_new(r.nested(r.type("UnityEngine.UI","ScrollRect"),"ScrollRectEvent"));uint32_t changedRoot=r.gchandle_new(changed,false);
  try{r.call(changed,".ctor");r.call(scroll,"set_onValueChanged",{"UnityEngine.UI.ScrollRect.ScrollRectEvent"},{changed});}catch(...){r.gchandle_free(changedRoot);throw;}r.gchandle_free(changedRoot);

  P addButton=r.resolve(r.klass("SettingItemsManager"),"AddButton",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","UnityEngine.Events.UnityAction[]"});
  NSArray*titles=@[@"\u8c31\u5e93\u7ba1\u7406",@"\u7ae0\u8282\u7ba1\u7406",@"\u76ae\u80a4 / \u97f3\u6548 / \u7279\u6548",@"\u9ad8\u7ea7\u53c2\u6570\uff08\u5224\u5b9a / HP / \u7ec3\u4e60\uff09"];
  for(int action=0;action<(int)titles.count;++action){P listeners=emptyListeners(r,addButton,1);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(addButton,nativeSettingsManager,{nativeTitle(r,titles[action]),listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);P button=r.get<P>(item,"button");emptyClick(r,button);nativeActions[button]=action;}
  P toggle=r.resolve(r.klass("SettingItemsManager"),"AddToggle",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Boolean","UnityEngine.Events.UnityAction<System.Boolean>[]"});
  for(NSArray*entry in @[@[@"autoplay",@"AutoPlay"],@[@"noise",@"\u566a\u57df"],@[@"clearOriginalNoise",@"\u6e05\u9664\u539f\u8c31\u566a\u57df"],@[@"hpEnabled",@"HP \u751f\u5b58"],@[@"fullScreen",@"\u5168\u5c4f\u5224\u5b9a"],@[@"accuracy",@"\u5b9e\u65f6 ACC"],@[@"noCombo",@"\u53bb\u9664\u8fde\u51fb\u5206"],@[@"practiceMode",@"\u533a\u95f4\u7ec3\u4e60"],@[@"showShortcuts",@"\u9009\u66f2\u5feb\u6377\u6309\u94ae"]]){
   bool value=PMSettingBool([entry[0]UTF8String]);P listeners=emptyListeners(r,toggle,2);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(toggle,nativeSettingsManager,{nativeTitle(r,entry[1]),&value,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,entry[0],value?1.f:0.f,false});
  }
  P slider=r.resolve(r.klass("SettingItemsManager"),"AddSlider",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Single","System.Single","System.Single","UnityEngine.Events.UnityAction<System.Single>[]"});
  float value=[[[PMSettings shared]value:@"opacity"]floatValue],low=0,high=1;P listeners=emptyListeners(r,slider,4);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(slider,nativeSettingsManager,{nativeTitle(r,@"\u60ac\u6d6e\u7a97\u900f\u660e\u5ea6"),&value,&low,&high,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,@"opacity",value,true});
  active(r,root,true);r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},{});
  r.call(nativeSettingsManager,"RefreshItems");r.call(nativeSettingsManager,"RefreshPosition");
  float top=1;r.call(scroll,"set_verticalNormalizedPosition",{"System.Single"},{&top});
  registerNativeTab(r,setting,r.component(root,r.type("UnityEngine","Animator")),content);
  changeNativeTab(r,setting,nativeTabIndex);
  // ChangeTab selects via the registered arrays (verified in iOS 4.0.3).
  // A clone of an inactive original frame can retain disabled raycast flags.
  P group=r.component(root,r.type("UnityEngine","CanvasGroup"));
  if(r.alive(group)){bool yes=true;float alpha=1;r.call(group,"set_alpha",{"System.Single"},{&alpha});r.call(group,"set_interactable",{"System.Boolean"},{&yes});r.call(group,"set_blocksRaycasts",{"System.Boolean"},{&yes});}
  if(r.get<int>(setting,"currentTab")!=nativeTabIndex||!r.unbox<bool>(r.call(root,"get_activeInHierarchy")))throw std::runtime_error("Native MOD tab did not become active");
  PMDiagnosticsWrite((std::string("MOD page active: ")+phimod::settingsRevision+" build="+phimod::buildRevision+" nativeTab=3").c_str());
  PMDiagnosticsWrite("MOD native fourth settings tab created: distinct viewport/content/itemsHolder");
 }catch(...){clearNativeSettings(r);throw;}
}
void pollNativeSettings(Runtime&r){
 P root=target(r,nativeSettingsRoot);if(!r.alive(root))return;
 PMModEditor*editor=[PMModEditor shared];if(nativeAdvanced&&editor.hidden){nativeAdvanced=false;active(r,root,true);for(auto&option:nativeOptions){float value=[[[PMSettings shared]value:option.key]floatValue];if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&value});else{bool on=value!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}option.last=value;}}
 if(nativeAdvanced)return;
 if(++nativeStableFrames==2)try{
  P owner=target(r,settingRoot),tr=transform(r,root);sceneimpl::Rect rect=r.unbox<sceneimpl::Rect>(r.call(tr,"get_rect"));V2 position=r.unbox<V2>(r.call(tr,"get_anchoredPosition"));
  char message[256];snprintf(message,sizeof(message),"MOD page stable: tab=%d active=%d pos=%.1f,%.1f size=%.1f,%.1f options=%lu",r.get<int>(owner,"currentTab"),r.unbox<bool>(r.call(root,"get_activeInHierarchy")),position.x,position.y,rect.w,rect.h,(unsigned long)nativeOptions.size());PMDiagnosticsWrite(message);
 }catch(const std::exception&e){PMDiagnosticsWrite((std::string("MOD page diagnostic: ")+e.what()).c_str());}
 r.call(nativeSettingsManager,"RefreshPosition");
 for(auto&option:nativeOptions){float value=option.slider?r.unbox<float>(r.call(option.item,"get_Value")):(r.unbox<bool>(r.call(option.item,"get_Value"))?1.f:0.f);if(std::fabs(value-option.last)<.0001f)continue;NSString*error=nil;if([[PMSettings shared]setValue:@(value) forKey:option.key error:&error])option.last=value;else{float old=option.last;if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&old});else{bool on=old!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}PMDiagnosticsWrite(error.UTF8String);}}
}
bool pressNativeSetting(Runtime&r,P button){auto found=nativeActions.find(button);if(found==nativeActions.end())return false;UIWindow*w=window();UIView*source=w.rootViewController.view;
 if(found->second==0)PMShowContent(source,NO);else if(found->second==1)PMShowContent(source,YES);else if(found->second==2)PMShowResourcePackPicker(source);else{nativeAdvanced=true;active(r,target(r,nativeSettingsRoot),false);[[PMModEditor shared]begin];[PMModEditor shared].hidden=NO;}
 return true;
}
}
