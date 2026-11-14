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
std::vector<std::pair<uint32_t,bool>>nativePageGraphics;
void restoreNativePageGraphics(Runtime&r){for(auto&entry:nativePageGraphics){P graphic=target(r,entry.first);if(r.alive(graphic))r.call(graphic,"set_enabled",{"System.Boolean"},{&entry.second});r.gchandle_free(entry.first);}nativePageGraphics.clear();}
void clearNativeSettings(Runtime&r){
 restoreNativePageGraphics(r);
 P setting=target(r,settingRoot);
 if(originalFrames&&r.alive(setting)){
  if(r.get<int>(setting,"currentTab")==nativeTabIndex)changeNativeTab(r,setting,nativePreviousTab);
  r.put(setting,"frameAnimators",target(r,originalFrames));r.put(setting,"tabAnimators",target(r,originalTabs));r.put(setting,"tabScrollContents",target(r,originalContents));
 }
 for(uint32_t*h:{&originalFrames,&originalTabs,&originalContents})if(*h){r.gchandle_free(*h);*h=0;}nativeTabIndex=-1;
 nativeStableFrames=0;tabTap.reset();nativeOptions.clear();nativeActions.clear();nativeSettingsManager=nullptr;nativeAdvanced=false;dispose(r,nativeSettingsRoot,true);
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
bool sameNativeTransform(Runtime&r,P a,P b){return a==b||(a&&b&&r.unbox<bool>(r.stat(r.type("UnityEngine","Object"),"op_Equality",{"UnityEngine.Object","UnityEngine.Object"},{a,b})));}
P enclosingCanvas(Runtime&r,P node){
 for(int depth=0;node&&depth<64;++depth,node=r.call(node,"get_parent")){P canvas=r.component(go(r,node),r.type("UnityEngine","Canvas"));if(r.alive(canvas))return canvas;}
 return nullptr;
}
bool childPath(Runtime&r,P source,P node,std::vector<int>&path){for(int depth=0;node&&!sameNativeTransform(r,node,source)&&depth<64;++depth){path.push_back(r.unbox<int>(r.call(node,"GetSiblingIndex")));node=r.call(node,"get_parent");}return sameNativeTransform(r,node,source);}
P followSettingsPath(Runtime&r,P clone,const std::vector<int>&path,const char*label){
 for(auto i=path.rbegin();i!=path.rend();++i){int index=*i,count=r.unbox<int>(r.call(clone,"get_childCount"));if(index<0||index>=count)throw std::runtime_error(std::string("Settings clone path mismatch: ")+label+" index="+std::to_string(index)+" children="+std::to_string(count));clone=r.call(clone,"GetChild",{"System.Int32"},{&index});}return clone;
}
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
void nativeManualLayout(Runtime&r,P tr){
 P object=go(r,tr),layout=r.component(object,r.type("UnityEngine.UI","LayoutElement"));
 if(!r.alive(layout))layout=r.call(object,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine.UI","LayoutElement")))});
 bool yes=true;r.call(layout,"set_ignoreLayout",{"System.Boolean"},{&yes});
}
void nativeRectRegion(Runtime&r,P tr,phimod::UIRegion region){
 V2 low{region.left,region.bottom},high{region.right,region.top},zero{0,0},center{.5f,.5f};V3 scale{1,1,1};struct Q{float x,y,z,w;};Q rotation{0,0,0,1};
 r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(tr,"set_pivot",{"UnityEngine.Vector2"},{&center});
 r.call(tr,"set_offsetMin",{"UnityEngine.Vector2"},{&zero});r.call(tr,"set_offsetMax",{"UnityEngine.Vector2"},{&zero});r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});r.call(tr,"set_localRotation",{"UnityEngine.Quaternion"},{&rotation});
}
void showNativePath(Runtime&r,P node,P root){
 for(int depth=0;node&&depth<32;++depth){
  P object=go(r,node);active(r,object,true);P group=r.component(object,r.type("UnityEngine","CanvasGroup"));
  if(r.alive(group)){float one=1;bool yes=true;r.call(group,"set_alpha",{"System.Single"},{&one});r.call(group,"set_interactable",{"System.Boolean"},{&yes});r.call(group,"set_blocksRaycasts",{"System.Boolean"},{&yes});}
  if(sameNativeTransform(r,node,root))return;node=r.call(node,"get_parent");
 }throw std::runtime_error("MOD content path escaped its independent frame");
}
phimod::UIRegion nativeWideViewport(Runtime&r,P setting,P frames){
 // Measure another native tab relative to its OWN frame. A hidden frame's
 // screen position must not be copied into the MOD page.
 for(int index:{1,2})try{
  P frame=r.arrayAt(frames,index),frameTr=transform(r,frame),scrolls=r.children(go(r,frame),r.type("UnityEngine.UI","ScrollRect"));
  if(!scrolls||!r.array_length(scrolls))continue;P expectedContent=r.arrayAt(r.get<P>(setting,"tabScrollContents"),index),scroll=nullptr;
  for(uintptr_t i=0;i<r.array_length(scrolls);++i){P candidate=r.arrayAt(scrolls,int(i));if(r.call(candidate,"get_content")==expectedContent){scroll=candidate;break;}}
  if(!scroll)continue;P viewport=r.call(scroll,"get_viewport");if(!r.alive(viewport))viewport=transform(r,scroll);
  auto b=bounds(r,viewport,frameTr);auto f=r.unbox<sceneimpl::Rect>(r.call(frameTr,"get_rect"));
  if(!std::isfinite(b.l)||!std::isfinite(b.r)||!std::isfinite(b.b)||!std::isfinite(b.t)||!(f.w>0&&f.h>0))continue;
  auto region=phimod::settingsViewport({b.l,b.b,b.r,b.t},{f.x,f.y,f.x+f.w,f.y+f.h});
  if(region.right-region.left>.6f)return region;
 }catch(const std::exception&){}
 return {.035f,.075f,.965f,.90f};
}
void nativeHorizontalFill(Runtime&r,P tr){
 V2 low=r.unbox<V2>(r.call(tr,"get_anchorMin")),high=r.unbox<V2>(r.call(tr,"get_anchorMax"));low.x=0;high.x=1;
 r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});
 V2 size=r.unbox<V2>(r.call(tr,"get_sizeDelta")),position=r.unbox<V2>(r.call(tr,"get_anchoredPosition"));size.x=position.x=0;V3 scale{1,1,1};
 r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(tr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&position});r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});
}
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
 P sourceTransform=transform(r,sourceFrame);
 if(r.array_length(frames)!=3)throw std::runtime_error("Unexpected original settings frame count");
 std::array<P,3>frameTransforms{transform(r,r.arrayAt(frames,0)),transform(r,r.arrayAt(frames,1)),transform(r,r.arrayAt(frames,2))};
 // Frame animators can live under an ordinary Transform, not a RectTransform.
 // Compare Unity object identity rather than requiring identical managed wrappers.
 P parent=phimod::settingsFrameHost(frameTransforms,[&](P node){return r.call(node,"get_parent");},[](P){return true;},[&](P a,P b){return sameNativeTransform(r,a,b);});
 P sourceCanvas=enclosingCanvas(r,transform(r,source));
 if(!r.alive(sourceCanvas))throw std::runtime_error("Native settings canvas unavailable");
 P canvasRoot=r.call(sourceCanvas,"get_rootCanvas");
 if(!parent)parent=r.call(transform(r,canvasRoot),"get_parent"); // Scene-root sibling for disconnected canvases.
 // A fallback host must also be outside every frame that ChangeTab hides.
 for(int depth=0;parent&&depth<64;++depth){bool inside=false;for(P frame:frameTransforms){std::vector<int>path;if(childPath(r,frame,parent,path)){inside=true;break;}}if(!inside)break;parent=r.call(parent,"get_parent");}

 // Serialized level10 frameAnimators[0] is the ROOT Canvas, not Play.
 // A root Canvas clone must retain its scaler/camera and remain outside the
 // original animated canvas. A non-canvas frame can share the source canvas.
 bool sourceIsRootCanvas=sameNativeTransform(r,sourceTransform,transform(r,canvasRoot));
 parent=sourceIsRootCanvas?r.call(transform(r,canvasRoot),"get_parent"):transform(r,canvasRoot);
 if(!sourceIsRootCanvas&&!r.alive(r.component(go(r,parent),r.type("UnityEngine","RectTransform"))))throw std::runtime_error("Settings canvas parent is not a RectTransform");
 int fromTab=std::clamp(r.get<int>(setting,"currentTab"),0,2);
 phimod::UIRegion bodyRegion{.11f,.08f,.94f,.86f};
 phimod::UIRegion wideRegion=sourceIsRootCanvas?bodyRegion:phimod::UIRegion{0,0,1,1};
 int frameLayer=parent?r.unbox<int>(r.call(parent,"get_childCount")):0;
 for(P frameTr:frameTransforms){std::vector<int>path;if(parent&&childPath(r,parent,frameTr,path)&&!path.empty())frameLayer=std::min(frameLayer,path.back()+1);}
 // Capture all source references before Instantiate/SetSiblingIndex can change sibling indices.
 std::array<std::vector<int>,4>templatePaths;std::array<P,4>templateNodes{transform(r,source),r.get<P>(original,"content"),r.get<P>(original,"viewport"),r.get<P>(original,"itemsHolder")};
 for(size_t i=0;i<templateNodes.size();++i)if(!childPath(r,sourceTransform,templateNodes[i],templatePaths[i]))throw std::runtime_error("Settings reference outside source frame");
 std::vector<std::vector<int>>decorationPaths;for(const char*field:{"previewNoteHolder","judgeLine","clickPosition"}){P object=r.get<P>(setting,field);if(!r.alive(object))continue;std::vector<int>path;if(childPath(r,sourceTransform,transform(r,object),path))decorationPaths.push_back(path);}
 // Instantiate under an inactive staging parent: copied Awake/OnEnable code
 // must not delete/reorder template children before references are resolved.
 P staging=r.object_new(r.type("UnityEngine","GameObject"));uint32_t stagingRoot=r.gchandle_new(staging,false);P root=nullptr;
 try{r.call(staging,".ctor",{"System.String"},{r.string_new("PhiMod Settings Staging")});active(r,staging,false);root=clone(r,go(r,sourceFrame),transform(r,staging),nativeSettingsRoot);active(r,root,false);bool no=false;r.call(transform(r,root),"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});}
 catch(...){r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{staging});r.gchandle_free(stagingRoot);throw;}
 r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{staging});r.gchandle_free(stagingRoot);
 r.call(root,"set_name",{"System.String"},{r.string_new("PhiMod Settings Frame")});
 // level10: FrameContainer owns an opaque Background. Insert AFTER that
 // branch, before TabBar/navigation; index zero puts every MOD row behind it.
 if(parent)r.call(transform(r,root),"SetSiblingIndex",{"System.Int32"},{&frameLayer});
 // Only the page visual/template is cloned. A copied Setting controller must
 // never run native Update or take ownership of the live settings session.
 P controllers=r.children(root,r.klass("Setting"));bool disabled=false;
 for(uintptr_t i=0;controllers&&i<r.array_length(controllers);++i)r.call(r.arrayAt(controllers,int(i)),"set_enabled",{"System.Boolean"},{&disabled});
 try{
  P cloneTransform=transform(r,root);
  // Freeze only copied template animators BEFORE adding new native controls.
  // Otherwise a clone made while Gameplay is hidden keeps writing its hidden pose.
  P copiedAnimators=r.children(root,r.type("UnityEngine","Animator"));bool no=false;
  for(uintptr_t i=0;copiedAnimators&&i<r.array_length(copiedAnimators);++i)r.call(r.arrayAt(copiedAnimators,int(i)),"set_enabled",{"System.Boolean"},{&no});
  P scalers=r.children(root,r.type("UnityEngine.UI","CanvasScaler"));for(uintptr_t i=0;scalers&&i<r.array_length(scalers);++i){P scaler=r.arrayAt(scalers,int(i));bool enable=sourceIsRootCanvas&&sameNativeTransform(r,transform(r,scaler),cloneTransform);r.call(scaler,"set_enabled",{"System.Boolean"},{&enable});}
  P canvases=r.children(root,r.type("UnityEngine","Canvas"));for(uintptr_t i=0;canvases&&i<r.array_length(canvases);++i)r.call(r.arrayAt(canvases,int(i)),"set_overrideSorting",{"System.Boolean"},{&no});
  if(sourceIsRootCanvas){P canvas=r.component(root,r.type("UnityEngine","Canvas"));bool yes=true;r.call(canvas,"set_enabled",{"System.Boolean"},{&yes});int order=r.unbox<int>(r.call(canvasRoot,"get_sortingOrder"))+1;r.call(canvas,"set_sortingOrder",{"System.Int32"},{&order});}
  else{nativeManualLayout(r,cloneTransform);nativeRectRegion(r,cloneTransform,bodyRegion);}
  P scrollTransform=followSettingsPath(r,cloneTransform,templatePaths[0],"scroll");
  P scroll=r.component(go(r,scrollTransform),r.type("UnityEngine.UI","ScrollRect"));
  P content=followSettingsPath(r,cloneTransform,templatePaths[1],"content");
  P viewport=followSettingsPath(r,cloneTransform,templatePaths[2],"viewport");
  P holder=followSettingsPath(r,cloneTransform,templatePaths[3],"itemsHolder");
  if(content==holder||viewport==holder)throw std::runtime_error("Native settings hierarchy must keep content and itemsHolder separate");
  // Hide gameplay-only decorations copied with the frame, not its viewport.
  for(const auto&path:decorationPaths){P mapped=followSettingsPath(r,cloneTransform,path,"decoration");active(r,go(r,mapped),false);}

  // Detach the whole scroll subtree from Gameplay's left-column container.
  // The content/itemsHolder relationship remains the native template's layout.
  if(scrollTransform!=cloneTransform){r.call(scrollTransform,"SetParent",{"UnityEngine.Transform","System.Boolean"},{cloneTransform,&no});nativeManualLayout(r,scrollTransform);nativeRectRegion(r,scrollTransform,wideRegion);}
  std::vector<int>viewportPath;
  if(viewport==cloneTransform){ /* Native self-viewport: keep the body rectangle. */ }
  else if(scrollTransform==cloneTransform||!childPath(r,scrollTransform,viewport,viewportPath)){
   r.call(viewport,"SetParent",{"UnityEngine.Transform","System.Boolean"},{cloneTransform,&no});nativeManualLayout(r,viewport);nativeRectRegion(r,viewport,wideRegion);
  }else{
   for(P node=viewport;!sameNativeTransform(r,node,scrollTransform);node=r.call(node,"get_parent"))nativeRectRegion(r,node,{0,0,1,1});
  }
  // The source animator owns the entire Canvas. Do not activate cloned Stats,
  // TabBar or account-page controllers while building the MOD page.
  int branchCount=r.unbox<int>(r.call(cloneTransform,"get_childCount"));
  for(int i=0;i<branchCount;++i){P branch=r.call(cloneTransform,"GetChild",{"System.Int32"},{&i});bool keep=false;for(P node:{scrollTransform,viewport,content,holder}){std::vector<int>path;if(childPath(r,branch,node,path)){keep=true;break;}}if(!keep)active(r,go(r,branch),false);}
  // Keep the serialized stretched top anchors and pivots from level10:
  // Content: min=(0,1), max=(1,1), pivot=(1,1); Items pivot=(0,1).
  // RefreshItems computes slanted insets using those anchors. Collapsing max.x
  // to zero yields a zero/negative content width and an entirely clipped page.
  for(P item:{content,holder}){V2 min{0,1},max{1,1};V3 one{1,1,1};r.call(item,"set_anchorMin",{"UnityEngine.Vector2"},{&min});r.call(item,"set_anchorMax",{"UnityEngine.Vector2"},{&max});r.call(item,"set_localScale",{"UnityEngine.Vector3"},{&one});}
  std::vector<uint32_t>oldRows;int rowCount=r.unbox<int>(r.call(holder,"get_childCount"));
  for(int i=0;i<rowCount;++i){P row=r.call(holder,"GetChild",{"System.Int32"},{&i});oldRows.push_back(r.gchandle_new(row,false));}
  try{for(uint32_t saved:oldRows){P row=target(r,saved);if(!r.alive(row))continue;P object=go(r,row);bool world=false;active(r,object,false);r.call(row,"SetParent",{"UnityEngine.Transform","System.Boolean"},{nullptr,&world});r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{object});}}
  catch(...){for(uint32_t saved:oldRows)r.gchandle_free(saved);throw;}for(uint32_t saved:oldRows)r.gchandle_free(saved);
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
  showNativePath(r,scrollTransform,cloneTransform);showNativePath(r,viewport,cloneTransform);showNativePath(r,content,cloneTransform);showNativePath(r,holder,cloneTransform);
   P cloneGraphics=r.children(root,r.type("UnityEngine.UI","Graphic"));for(uintptr_t i=0;cloneGraphics&&i<r.array_length(cloneGraphics);++i){P graphic=r.arrayAt(cloneGraphics,int(i));std::vector<int>path;if(!childPath(r,scrollTransform,transform(r,graphic),path))r.call(graphic,"set_enabled",{"System.Boolean"},{&no});}
   active(r,root,true);r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},{});

  r.call(nativeSettingsManager,"RefreshItems");r.call(nativeSettingsManager,"RefreshPosition");
  r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases",{},{});
  auto contentRect=r.unbox<sceneimpl::Rect>(r.call(content,"get_rect")),holderRect=r.unbox<sceneimpl::Rect>(r.call(holder,"get_rect"));
  if(contentRect.w<=0||holderRect.w<=0||r.unbox<int>(r.call(holder,"get_childCount"))==0)throw std::runtime_error("MOD native layout produced empty/zero-width content");
  char geometry[180];snprintf(geometry,sizeof(geometry),"MOD layout widths content=%.1f items=%.1f rows=%d sibling=%d",contentRect.w,holderRect.w,r.unbox<int>(r.call(holder,"get_childCount")),r.unbox<int>(r.call(cloneTransform,"GetSiblingIndex")));PMDiagnosticsWrite(geometry);

  float top=1;r.call(scroll,"set_verticalNormalizedPosition",{"System.Single"},{&top});
  registerNativeTab(r,setting,r.component(root,r.type("UnityEngine","Animator")),content);
  changeNativeTab(r,setting,nativeTabIndex);
   P stockFrames=target(r,originalFrames),tabs=target(r,originalTabs);std::vector<P>seen;
   for(uintptr_t f=0;stockFrames&&f<r.array_length(stockFrames);++f){P frame=r.arrayAt(stockFrames,int(f)),graphics=r.children(go(r,frame),r.type("UnityEngine.UI","Graphic"));for(uintptr_t i=0;graphics&&i<r.array_length(graphics);++i){P graphic=r.arrayAt(graphics,int(i)),tr=transform(r,graphic);std::vector<int>path;bool protect=childPath(r,cloneTransform,tr,path);for(uintptr_t t=0;!protect&&tabs&&t<r.array_length(tabs);++t){path.clear();protect=childPath(r,transform(r,r.arrayAt(tabs,int(t))),tr,path);}if(protect||std::find(seen.begin(),seen.end(),graphic)!=seen.end())continue;seen.push_back(graphic);bool enabled=r.unbox<bool>(r.call(graphic,"get_enabled"));nativePageGraphics.push_back({r.gchandle_new(graphic,false),enabled});r.call(graphic,"set_enabled",{"System.Boolean"},{&no});}}

  // ChangeTab selects via the registered arrays (verified in iOS 4.0.3).
  // A clone of an inactive original frame can retain disabled raycast flags.
  P group=r.component(root,r.type("UnityEngine","CanvasGroup"));
  if(r.alive(group)){bool yes=true;float alpha=1;r.call(group,"set_alpha",{"System.Single"},{&alpha});r.call(group,"set_interactable",{"System.Boolean"},{&yes});r.call(group,"set_blocksRaycasts",{"System.Boolean"},{&yes});}
  if(r.get<int>(setting,"currentTab")!=nativeTabIndex||!r.unbox<bool>(r.call(root,"get_activeInHierarchy")))throw std::runtime_error("Native MOD tab did not become active");
  PMDiagnosticsWrite((std::string("MOD page active: ")+phimod::settingsRevision+" build="+phimod::buildRevision+" nativeTab=3").c_str());
  PMDiagnosticsWrite("MOD native fourth settings tab created: distinct viewport/content/itemsHolder");
  char layout[180];snprintf(layout,sizeof(layout),"MOD independent full-width page: fromTab=%d viewport=%.3f,%.3f..%.3f,%.3f",fromTab,wideRegion.left,wideRegion.bottom,wideRegion.right,wideRegion.top);PMDiagnosticsWrite(layout);
 }catch(...){clearNativeSettings(r);throw;}
}
void pollNativeSettings(Runtime&r){
 P root=target(r,nativeSettingsRoot);if(!r.alive(root))return;
 PMModEditor*editor=[PMModEditor shared];if(nativeAdvanced&&editor.hidden){nativeAdvanced=false;active(r,root,true);for(auto&option:nativeOptions){float value=[[[PMSettings shared]value:option.key]floatValue];if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&value});else{bool on=value!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}option.last=value;}}
 if(nativeAdvanced)return;
 for(auto&entry:nativePageGraphics){P graphic=target(r,entry.first);if(r.alive(graphic)&&r.unbox<bool>(r.call(graphic,"get_enabled"))){bool no=false;r.call(graphic,"set_enabled",{"System.Boolean"},{&no});}}
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
