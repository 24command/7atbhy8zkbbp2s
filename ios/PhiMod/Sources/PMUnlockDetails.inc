// Native button + native MsgBox with a scrollable body. No save-sync callbacks.
uint32_t requirementRoot=0,requirementPopup=0;P requirementButton=nullptr,requirementGraphic=nullptr;
bool requirementVisible=false;float requirementCut=0;phimod::UITapGate requirementTap;
uint32_t requirementTask=0;bool requirementScrollPending=false,requirementSeenShowing=false;double requirementPressedAt=-100,requirementPopupSince=0;NSString*requirementPopupText=nil;
P requirementTouchItem=nullptr;int requirementTouchSlot=-1;
void clearRequirementUI(Runtime&r){
 requirementVisible=false;requirementTap.reset();requirementTouchItem=nullptr;requirementTouchSlot=-1;requirementGraphic=nullptr;requirementScrollPending=false;requirementSeenShowing=false;requirementPopupText=nil;
 if(requirementTask){r.gchandle_free(requirementTask);requirementTask=0;}
 if(requirementPopup){P popup=target(r,requirementPopup);if(r.alive(popup))try{r.call(popup,"Cancel");}catch(...){}r.gchandle_free(requirementPopup);requirementPopup=0;}
 if(requirementRoot){P go=target(r,requirementRoot);if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(requirementRoot);requirementRoot=0;}requirementButton=nullptr;
}
// This is deliberately NOT a clone of Start/Select: their CanvasGroups,
// animators and sliced decorations inherit the locked song's disabled state.
P requirementObject(Runtime&r,const char*name,P parent){
 P object=r.object_new(r.type("UnityEngine","GameObject"));uint32_t handle=r.gchandle_new(object,false);
 try{r.call(object,".ctor",{"System.String"},{r.string_new(name)});
  P rect=r.call(object,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine","RectTransform")))});
  bool no=false;r.call(rect,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});
  int layer=r.unbox<int>(r.call(r.call(parent,"get_gameObject"),"get_layer"));r.call(object,"set_layer",{"System.Int32"},{&layer});
 }catch(...){r.gchandle_free(handle);throw;}r.gchandle_free(handle);return object;
}
P requirementComponent(Runtime&r,P object,const char*ns,const char*name){return r.call(object,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});}
void showRequirementButton(Runtime&r,P tip,bool visible){
 bool no=false,yes=true;
 if(visible!=requirementVisible){requirementVisible=visible;requirementTap.reset();}
 if(visible&&!requirementRoot){
  if(!r.alive(tip))return;P parent=r.call(r.call(tip,"get_transform"),"get_parent");
  P object=requirementObject(r,"PhiMod Unlock Details",parent);requirementRoot=r.gchandle_new(object,false);
  try{
   P rect=r.call(object,"get_transform"),image=requirementComponent(r,object,"Lean.Gui","LeanPolygon");
   requirementGraphic=image;float fill=-1,blur=1;r.call(image,"set_Thickness",{"System.Single"},{&fill});r.call(image,"set_Blur",{"System.Single"},{&blur});
   // Use the same filled polygon graphic as the game, not a stretched sprite.
   TipColor background{.94f,.96f,.98f,1};r.call(image,"set_color",{"UnityEngine.Color"},{&background});
   r.call(image,"set_maskable",{"System.Boolean"},{&no});r.call(image,"set_raycastTarget",{"System.Boolean"},{&yes});
   P group=requirementComponent(r,object,"UnityEngine","CanvasGroup");
   r.call(group,"set_ignoreParentGroups",{"System.Boolean"},{&yes});r.call(group,"set_interactable",{"System.Boolean"},{&yes});r.call(group,"set_blocksRaycasts",{"System.Boolean"},{&yes});
   requirementButton=requirementComponent(r,object,"UnityEngine.UI","Button");
   r.call(requirementButton,"set_targetGraphic",{"UnityEngine.UI.Graphic"},{image});r.call(requirementButton,"set_interactable",{"System.Boolean"},{&yes});
   P caption=requirementObject(r,"Caption",rect),label=requirementComponent(r,caption,"UnityEngine.UI","Text"),labelRect=r.call(caption,"get_transform");
   TipSize low{0,0},high{1,1},padding{-32,-8},zero{0,0};
   r.call(labelRect,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(labelRect,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(labelRect,"set_sizeDelta",{"UnityEngine.Vector2"},{&padding});r.call(labelRect,"set_anchoredPosition",{"UnityEngine.Vector2"},{&zero});
   r.call(label,"set_font",{"UnityEngine.Font"},{r.call(tip,"get_font")});r.call(label,"set_text",{"System.String"},{r.managedString(@"\u67e5\u770b\u89e3\u9501\u6761\u4ef6")});
   int font=28,center=4,overflow=1;r.call(label,"set_fontSize",{"System.Int32"},{&font});r.call(label,"set_alignment",{"UnityEngine.TextAnchor"},{&center});r.call(label,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&overflow});
   r.call(label,"set_resizeTextForBestFit",{"System.Boolean"},{&no});r.call(label,"set_raycastTarget",{"System.Boolean"},{&no});r.call(label,"set_maskable",{"System.Boolean"},{&no});
   TipColor foreground{.09f,.12f,.17f,1};r.call(label,"set_color",{"UnityEngine.Color"},{&foreground});
   PMDiagnosticsWrite("Unlock details v3: native LeanPolygon button ready");
  }catch(...){clearRequirementUI(r);throw;}
 }
 P object=target(r,requirementRoot);if(!r.alive(object))return;
 if(visible){P tipRect=r.call(tip,"get_transform"),rect=r.call(object,"get_transform");
  // Use the tip's actual rectangle, not its stretch-anchor sizeDelta (often 0).
  struct Rect{float x,y,w,h;};Rect bounds=r.unbox<Rect>(r.call(tipRect,"get_rect"));
  struct V3{float x,y,z;};V3 center{bounds.x+bounds.w*.5f,bounds.y+bounds.h*.5f,0};
  V3 world=r.unbox<V3>(r.call(tipRect,"TransformPoint",{"UnityEngine.Vector3"},{&center})),one{1,1,1};
  TipSize anchor{.5f,.5f},size{std::clamp(bounds.w,240.f,420.f),64.f};
  r.call(rect,"set_anchorMin",{"UnityEngine.Vector2"},{&anchor});r.call(rect,"set_anchorMax",{"UnityEngine.Vector2"},{&anchor});r.call(rect,"set_pivot",{"UnityEngine.Vector2"},{&anchor});
  // Rebuild only when its native geometry changes. Negative thickness fills
  // the polygon (zero would draw no body in this game's LeanPolygon).
  float inverse=std::fabs(r.unbox<float>(r.stat(r.type("Phigros.UI","MsgBox"),"get_InverseSlope")));
  float cut=std::min(size.x*.25f,size.y*inverse);
  P points=r.call(requirementGraphic,"get_Points");
  if(r.count(points)!=4||std::fabs(cut-requirementCut)>.01f){
   requirementCut=cut;r.call(points,"Clear");struct V4{float x,y,z,w;};
   // Clockwise quad with the native XY offsets / ZW normalized anchors.
   V4 vertices[]={{0,0,0,0},{cut,0,0,1},{0,0,1,1},{-cut,0,1,0}};
   for(auto&vertex:vertices)r.call(points,"Add",{"UnityEngine.Vector4"},{&vertex});r.call(requirementGraphic,"SetVerticesDirty");
  }
  r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(rect,"set_localScale",{"UnityEngine.Vector3"},{&one});r.call(rect,"set_position",{"UnityEngine.Vector3"},{&world});r.call(rect,"SetAsLastSibling");
 }
 lockActive(r,object,visible);
 if(tip){bool enabled=!visible;r.call(tip,"set_enabled",{"System.Boolean"},{&enabled});}
}
// Keep the stock message box alive even if optional scroll layout fails.
// Its UniTask remains rooted until the native dialog has closed.
void releaseRequirementDialog(Runtime&r){
 if(requirementTask){r.gchandle_free(requirementTask);requirementTask=0;}
 if(requirementPopup){r.gchandle_free(requirementPopup);requirementPopup=0;}
 requirementScrollPending=false;requirementSeenShowing=false;requirementPopupText=nil;
}
void prepareRequirementScroll(Runtime&r,P popup){
 bool no=false,yes=true;P content=nullptr,oldTr=nullptr,oldParent=nullptr,viewObject=nullptr;uint32_t viewHandle=0;
 try{
  r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases");
  content=r.get<P>(popup,"content");oldTr=r.call(content,"get_rectTransform");oldParent=r.call(oldTr,"get_parent");
  int font=28,wrap=0,overflow=1,align=0;
  r.call(content,"set_fontSize",{"System.Int32"},{&font});r.call(content,"set_resizeTextForBestFit",{"System.Boolean"},{&no});r.call(content,"set_supportRichText",{"System.Boolean"},{&no});
  r.call(content,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&wrap});r.call(content,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&overflow});r.call(content,"set_alignment",{"UnityEngine.TextAnchor"},{&align});r.call(content,"set_raycastTarget",{"System.Boolean"},{&yes});
  viewObject=requirementObject(r,"PhiMod Unlock Scroll",oldParent);viewHandle=r.gchandle_new(viewObject,false);P view=r.call(viewObject,"get_transform");
  for(const char*field:{"anchorMin","anchorMax","pivot","sizeDelta","anchoredPosition"}){std::string get=std::string("get_")+field,set=std::string("set_")+field;TipSize value=r.unbox<TipSize>(r.call(oldTr,get.c_str()));r.call(view,set.c_str(),{"UnityEngine.Vector2"},{&value});}
  requirementComponent(r,viewObject,"UnityEngine.UI","RectMask2D");
  P image=requirementComponent(r,viewObject,"UnityEngine.UI","Image");TipColor transparent{0,0,0,0};r.call(image,"set_color",{"UnityEngine.Color"},{&transparent});r.call(image,"set_raycastTarget",{"System.Boolean"},{&yes});
  P scroll=requirementComponent(r,viewObject,"UnityEngine.UI","ScrollRect");
  r.call(oldTr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{view,&no});
  TipSize low{0,1},high{1,1},pivot{.5f,1},position{0,0},size{0,32};
  r.call(oldTr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(oldTr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(oldTr,"set_pivot",{"UnityEngine.Vector2"},{&pivot});r.call(oldTr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&position});r.call(oldTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
  r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases");
  float height=r.unbox<float>(r.call(content,"get_preferredHeight"));size.y=std::max(32.f,height+24);r.call(oldTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
  r.call(scroll,"set_viewport",{"UnityEngine.RectTransform"},{view});r.call(scroll,"set_content",{"UnityEngine.RectTransform"},{oldTr});r.call(scroll,"set_horizontal",{"System.Boolean"},{&no});r.call(scroll,"set_vertical",{"System.Boolean"},{&yes});
  int clamped=2;r.call(scroll,"set_movementType",{"UnityEngine.UI.ScrollRect.MovementType"},{&clamped});float top=1;r.call(scroll,"set_verticalNormalizedPosition",{"System.Single"},{&top});
  PMDiagnosticsWrite("Unlock details native scroll ready");
 }catch(const std::exception&e){
  // Restore the stock content BEFORE disposing a partially built viewport.
  // Never Cancel() a visible native dialog just because scrolling failed.
  try{if(oldTr&&oldParent){r.call(oldTr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{oldParent,&no});r.call(popup,"RefreshElements");}if(viewObject)r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{viewObject});}catch(...){}
  logf("Unlock details scroll setup failed; native dialog retained: %s",e.what());
 }
 if(viewHandle)r.gchandle_free(viewHandle);
}
void pollRequirementDialog(Runtime&r){
 if(!requirementPopup)return;P popup=target(r,requirementPopup);
 if(!r.alive(popup)){releaseRequirementDialog(r);return;}
 if(!r.get<bool>(popup,"isShowing")){
  if(requirementSeenShowing||!requirementScrollPending){releaseRequirementDialog(r);return;}
  if(NSDate.timeIntervalSinceReferenceDate-requirementPopupSince>2){
   NSString*text=requirementPopupText;try{r.call(popup,"Cancel");}catch(...){}releaseRequirementDialog(r);
   PMDiagnosticsWrite("Unlock details Show timeout; requesting stock info dialog");
   r.stat(r.klass("PhigrosUI"),"ShowOkMessageBox",{"System.String","System.String"},{r.managedString(@"\u89e3\u9501\u6761\u4ef6"),r.managedString(text?:@"")});
  }return;
 }
 requirementSeenShowing=true;
 if(requirementScrollPending){requirementScrollPending=false;prepareRequirementScroll(r,popup);}
}
bool anotherRequirementDialog(Runtime&r){
 if(requirementPopup)return true;
 // Do not click through the game's existing native information dialogs.
 P dialogs=r.stat(r.type("UnityEngine","Object"),"FindObjectsOfType",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("Phigros.UI","MsgBox")))});
 for(uintptr_t i=0;dialogs&&i<r.array_length(dialogs);++i){P dialog=r.arrayAt(dialogs,int(i));if(r.alive(dialog)&&r.get<bool>(dialog,"isShowing"))return true;}return false;
}
void openRequirementPopup(Runtime&r,NSString*text){
 if(!text.length||requirementPopup)return;
 bool no=false;
 P popup=r.stat(r.klass("PhigrosUI"),"CreateMessageBox",{"System.String","System.String","System.Boolean"},{r.managedString(@"\u89e3\u9501\u6761\u4ef6"),r.managedString(text),&no});
 if(!r.alive(popup))throw std::runtime_error("Native message box not created");requirementPopup=r.gchandle_new(popup,false);requirementPopupText=[text copy];requirementPopupSince=NSDate.timeIntervalSinceReferenceDate;
 try{
  TipSize box{1000,660};r.call(popup,"set_Size",{"UnityEngine.Vector2"},{&box});
  P task=r.call(popup,"Show");if(task)requirementTask=r.gchandle_new(task,false);
  requirementScrollPending=true;requirementSeenShowing=r.get<bool>(popup,"isShowing");
  logf("Unlock details native Show dispatched: showing=%d chars=%lu",r.get<bool>(popup,"isShowing"),(unsigned long)text.length);
 }catch(...){try{r.call(popup,"Cancel");}catch(...){}releaseRequirementDialog(r);throw;}
}
void activateRequirement(Runtime&r,const char*source){
 if(!requirementVisible||!lockUIBlocked||!lockUIDetails.length||PMUnlockMediaBusy())return;
 P owner=target(r,lockUIOwner);if(!r.alive(owner)||r.get<bool>(owner,"exit"))return;
 double now=NSDate.timeIntervalSinceReferenceDate;if(now-requirementPressedAt<.4||anotherRequirementDialog(r))return;
 requirementPressedAt=now;requirementTap.reset();logf("Unlock details activate: source=%s",source);
 try{openRequirementPopup(r,lockUIDetails);}catch(const std::exception&e){
  logf("Unlock details custom popup failed; requesting stock info dialog: %s",e.what());
  r.stat(r.klass("PhigrosUI"),"ShowOkMessageBox",{"System.String","System.String"},{r.managedString(@"\u89e3\u9501\u6761\u4ef6"),r.managedString(lockUIDetails)});
 }
}
// Unity Touch payload from the 4.0.3 metadata. Runtime::unbox additionally
// verifies its actual managed value size before copying; no raw object offsets.
struct RequirementTouch{int finger;TipSize position,raw,delta;float dt;int taps,phase,type;float pressure,maxPressure,radius,radiusVariance,altitude,azimuth;};
static_assert(sizeof(RequirementTouch)==68,"Unity Touch payload");
bool requirementContains(Runtime&r,TipSize screen){
 P object=target(r,requirementRoot);if(!r.alive(object)||!r.alive(requirementGraphic)||!r.unbox<bool>(r.call(object,"get_activeInHierarchy")))return false;
 P canvas=r.call(requirementGraphic,"get_canvas");if(!r.alive(canvas))return false;
 P camera=nullptr;if(r.enumValue(r.call(canvas,"get_renderMode"),"UnityEngine.RenderMode")!=0)camera=r.call(canvas,"get_worldCamera");
 P rect=r.call(object,"get_transform");TipSize local{};
 if(!r.unbox<bool>(r.stat(r.type("UnityEngine","RectTransformUtility"),"ScreenPointToLocalPointInRectangle",{"UnityEngine.RectTransform","UnityEngine.Vector2","UnityEngine.Camera","UnityEngine.Vector2&"},{rect,&screen,camera,&local})))return false;
 struct Rect{float x,y,w,h;};Rect b=r.unbox<Rect>(r.call(rect,"get_rect"));
 return phimod::UIParallelogram{b.x,b.y,b.w,b.h,requirementCut}.contains(local.x,local.y);
}
void pollRequirementInput(Runtime&r,P selector){
 (void)selector;pollRequirementDialog(r);
 if(!requirementVisible||!lockUIBlocked||requirementPopup||PMUnlockMediaBusy()){requirementTap.reset();return;}
 P input=r.type("UnityEngine","Input");int count=r.unbox<int>(r.stat(input,"get_touchCount"));
 if(count!=1){requirementTap.reset();return;}int zero=0;
 auto touch=r.unbox<RequirementTouch>(r.stat(input,"GetTouch",{"System.Int32"},{&zero}));
 float screenWidth=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_width"));float slop=std::clamp(screenWidth*.012f,12.f,32.f);
 if(touch.phase==0){
  if(requirementContains(r,touch.position)&&!anotherRequirementDialog(r)){
   requirementTap.begin(touch.finger,touch.position.x,touch.position.y);requirementTouchItem=lockUIItem;requirementTouchSlot=lockUISlot;
   PMDiagnosticsWrite("Unlock details touch began inside native polygon");
  }else requirementTap.reset();
 }else if(touch.phase==4){requirementTap.reset();}
 else if(touch.phase==3){
  bool same=requirementTouchItem==lockUIItem&&requirementTouchSlot==lockUISlot;
  if(requirementTap.finish(touch.finger,touch.position.x,touch.position.y,slop,same&&requirementContains(r,touch.position)))activateRequirement(r,"touch-fallback");
 }else requirementTap.move(touch.finger,touch.position.x,touch.position.y,slop);
}
