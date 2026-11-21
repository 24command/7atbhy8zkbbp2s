// Native button + native MsgBox with a scrollable body. No save-sync callbacks.
uint32_t requirementRoot=0,requirementPopup=0;P requirementButton=nullptr,requirementGraphic=nullptr;
bool requirementVisible=false;float requirementCut=0;phimod::UITapGate requirementTap;
uint32_t requirementTask=0;bool requirementScrollPending=false,requirementSeenShowing=false;double requirementPressedAt=-100,requirementPopupSince=0;NSString*requirementPopupText=nil;
P requirementTouchItem=nullptr;int requirementTouchSlot=-1;
uint32_t requirementInputOwner=0,requirementView=0,requirementStockText=0;
bool requirementPreviousDisabled=false,requirementStockEnabled=true,requirementFallbackPending=false;
P requirementScroll=nullptr,requirementBody=nullptr;TipSize requirementBoxSize{},requirementBodySize{};
void resetRequirementGesture(Runtime&r,P owner){
 // Exact 4.0.3 constructor/no-touch sentinels, not a guessed finger id of -1.
 r.put(owner,"nowFingerId",-100);r.put(owner,"fingerOnSongList",false);
 r.put(owner,"startFingerPosition",-1000.f);r.put(owner,"startListPosition",-1000.f);
 r.put(owner,"listMoveSpeed",0.f);r.put(owner,"moveRecCount",0);r.put(owner,"moveRecCountForSongCoverSelector",0);
}
void releaseRequirementInput(Runtime&r){
 if(!requirementInputOwner)return;P owner=target(r,requirementInputOwner);
 if(r.alive(owner)){
  try{resetRequirementGesture(r,owner);}catch(const std::exception&e){logf("Unlock selector gesture reset: %s",e.what());}
  try{if(!requirementPreviousDisabled)r.put(owner,"disableSongSelector",requirementPreviousDisabled);}catch(const std::exception&e){logf("Unlock selector input restore: %s",e.what());}
 }
 r.gchandle_free(requirementInputOwner);requirementInputOwner=0;requirementTap.reset();
}
void acquireRequirementInput(Runtime&r,P owner){
 if(requirementInputOwner)return;
 P type=r.klass("SongSelector");
 for(const char*field:{"nowFingerId","moveRecCount","moveRecCountForSongCoverSelector"})r.field(type,field,"System.Int32",false);
 for(const char*field:{"startFingerPosition","startListPosition","listMoveSpeed"})r.field(type,field,"System.Single",false);
 for(const char*field:{"disableSongSelector","fingerOnSongList"})r.field(type,field,"System.Boolean",false);
 requirementPreviousDisabled=r.get<bool>(owner,"disableSongSelector");requirementInputOwner=r.gchandle_new(owner,false);
 try{guardLockedPreview(r,lockUIItem,lockUIManaged&&lockUIBlocked);if(!requirementPreviousDisabled)r.put(owner,"disableSongSelector",true);resetRequirementGesture(r,owner);}catch(...){releaseRequirementInput(r);throw;}
 PMDiagnosticsWrite("Unlock details owns selector input; native scrolling suspended");
}
void clearRequirementScroll(Runtime&r){
 P stock=target(r,requirementStockText),view=target(r,requirementView);
 try{if(r.alive(stock))r.call(stock,"set_enabled",{"System.Boolean"},{&requirementStockEnabled});}catch(const std::exception&e){logf("Unlock stock text restore: %s",e.what());}
 try{if(r.alive(view)){bool no=false;r.call(view,"SetActive",{"System.Boolean"},{&no});r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{view});}}catch(const std::exception&e){logf("Unlock scroll cleanup: %s",e.what());}
 for(uint32_t*handle:{&requirementStockText,&requirementView})if(*handle){r.gchandle_free(*handle);*handle=0;}
 requirementScroll=requirementBody=nullptr;requirementBodySize={};
}
void clearRequirementUI(Runtime&r){
 releaseRequirementInput(r);clearRequirementScroll(r);requirementFallbackPending=false;requirementBoxSize={};
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
   TipSize low{0,0},high{1,1},padding{-20,-8},zero{0,0};
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
  struct V3{float x,y,z;};V3 center{bounds.x+bounds.w*.5f+48.f,bounds.y+bounds.h*.5f,0};
  V3 world=r.unbox<V3>(r.call(tipRect,"TransformPoint",{"UnityEngine.Vector3"},{&center})),one{1,1,1};
  TipSize anchor{.5f,.5f},size{std::clamp(bounds.w,210.f,250.f),56.f};
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
 clearRequirementScroll(r);
 if(requirementTask){r.gchandle_free(requirementTask);requirementTask=0;}
 if(requirementPopup){r.gchandle_free(requirementPopup);requirementPopup=0;}
 requirementScrollPending=false;requirementSeenShowing=false;requirementFallbackPending=false;requirementPopupText=nil;requirementBoxSize={};
 // Input ownership is released by selectorModalUpdate only AFTER all fingers
 // are up. Scene teardown uses clearRequirementUI and restores immediately.
}
void sizeRequirementDialog(Runtime&r,P popup){
 P source=r.get<P>(popup,"content"),canvas=r.call(source,"get_canvas");if(!r.alive(canvas))return;
 P root=r.call(canvas,"get_rootCanvas");if(!r.alive(root))root=canvas;
 struct PopupRect{float x,y,w,h;};auto area=r.unbox<PopupRect>(r.call(r.call(root,"get_transform"),"get_rect"));
 auto safe=r.unbox<PopupRect>(r.stat(r.type("UnityEngine","Screen"),"get_safeArea"));
 int pixelsW=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_width")),pixelsH=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_height"));
 float width=area.w,height=area.h;if(pixelsW>0&&pixelsH>0&&safe.w>0&&safe.h>0){width*=std::min(1.f,safe.w/pixelsW);height*=std::min(1.f,safe.h/pixelsH);}
 auto targetSize=phimod::readablePopupSize(width,height);TipSize size{targetSize.width,targetSize.height};
 if(std::fabs(size.x-requirementBoxSize.x)<.5f&&std::fabs(size.y-requirementBoxSize.y)<.5f)return;
 r.call(popup,"set_Size",{"UnityEngine.Vector2"},{&size});requirementBoxSize=size;
 logf("Unlock details adaptive box: %.1f x %.1f (canvas %.1f x %.1f)",size.x,size.y,width,height);
}
void syncRequirementScroll(Runtime&r){
 P stock=target(r,requirementStockText),viewObject=target(r,requirementView);if(!r.alive(stock)||!r.alive(viewObject)||!r.alive(requirementBody))return;
 P stockTr=r.call(stock,"get_rectTransform"),view=r.call(viewObject,"get_transform");bool no=false;
 // The native Text NEVER changes parent. MsgBox.RefreshElements remains free
 // to lay it out; this sibling viewport follows that rectangle exactly once.
 for(const char*field:{"anchorMin","anchorMax","pivot","sizeDelta","anchoredPosition"}){
  std::string get=std::string("get_")+field,set=std::string("set_")+field;auto expected=r.unbox<TipSize>(r.call(stockTr,get.c_str())),actual=r.unbox<TipSize>(r.call(view,get.c_str()));
  if(expected.x!=actual.x||expected.y!=actual.y)r.call(view,set.c_str(),{"UnityEngine.Vector2"},{&expected});
 }
 struct PopupRect{float x,y,w,h;};auto rect=r.unbox<PopupRect>(r.call(view,"get_rect"));
 if(std::fabs(rect.w-requirementBodySize.x)>.5f||std::fabs(rect.h-requirementBodySize.y)>.5f){
  float normalized=requirementBodySize.x>0?r.unbox<float>(r.call(requirementScroll,"get_verticalNormalizedPosition")):1.f;
  P bodyTr=r.call(requirementBody,"get_rectTransform");r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases");
  float height=r.unbox<float>(r.call(requirementBody,"get_preferredHeight"));TipSize size{0,std::max(std::max(32.f,rect.h),height+20.f)};
  r.call(bodyTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});if(!std::isfinite(normalized))normalized=1;normalized=std::clamp(normalized,0.f,1.f);r.call(requirementScroll,"set_verticalNormalizedPosition",{"System.Single"},{&normalized});requirementBodySize={rect.w,rect.h};
 }
 if(r.unbox<bool>(r.call(stock,"get_enabled")))r.call(stock,"set_enabled",{"System.Boolean"},{&no});
}
void prepareRequirementScroll(Runtime&r,P popup){
 bool no=false,yes=true;
 try{
  sizeRequirementDialog(r,popup);r.stat(r.type("UnityEngine","Canvas"),"ForceUpdateCanvases");
  P stock=r.get<P>(popup,"content"),stockTr=r.call(stock,"get_rectTransform"),parent=r.call(stockTr,"get_parent");
  requirementStockEnabled=r.unbox<bool>(r.call(stock,"get_enabled"));requirementStockText=r.gchandle_new(stock,false);
  P viewObject=requirementObject(r,"PhiMod Unlock Scroll",parent);requirementView=r.gchandle_new(viewObject,false);P view=r.call(viewObject,"get_transform");
  P layout=requirementComponent(r,viewObject,"UnityEngine.UI","LayoutElement");r.call(layout,"set_ignoreLayout",{"System.Boolean"},{&yes});
  int bodyLayer=r.unbox<int>(r.call(stockTr,"GetSiblingIndex"))+1;r.call(view,"SetSiblingIndex",{"System.Int32"},{&bodyLayer});
  requirementComponent(r,viewObject,"UnityEngine.UI","RectMask2D");
  P hit=requirementComponent(r,viewObject,"UnityEngine.UI","Image");TipColor transparent{0,0,0,0};r.call(hit,"set_color",{"UnityEngine.Color"},{&transparent});r.call(hit,"set_raycastTarget",{"System.Boolean"},{&yes});
  requirementScroll=requirementComponent(r,viewObject,"UnityEngine.UI","ScrollRect");
  P textObject=requirementObject(r,"Unlock Requirements Body",view);requirementBody=requirementComponent(r,textObject,"UnityEngine.UI","Text");P bodyTr=r.call(textObject,"get_transform");
  int font=std::clamp(r.unbox<int>(r.call(stock,"get_fontSize")),28,36),wrap=0,overflow=1,align=0;
  r.call(requirementBody,"set_font",{"UnityEngine.Font"},{r.call(stock,"get_font")});r.call(requirementBody,"set_text",{"System.String"},{r.managedString(requirementPopupText?:lockUIDetails?:@"")});
  auto color=r.unbox<TipColor>(r.call(stock,"get_color"));color.a=1;r.call(requirementBody,"set_color",{"UnityEngine.Color"},{&color});
  r.call(requirementBody,"set_fontSize",{"System.Int32"},{&font});r.call(requirementBody,"set_resizeTextForBestFit",{"System.Boolean"},{&no});r.call(requirementBody,"set_supportRichText",{"System.Boolean"},{&yes});r.call(requirementBody,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&wrap});r.call(requirementBody,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&overflow});r.call(requirementBody,"set_alignment",{"UnityEngine.TextAnchor"},{&align});r.call(requirementBody,"set_raycastTarget",{"System.Boolean"},{&yes});
  TipSize low{0,1},high{1,1},pivot{.5f,1},zero{0,0},size{0,32};r.call(bodyTr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(bodyTr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(bodyTr,"set_pivot",{"UnityEngine.Vector2"},{&pivot});r.call(bodyTr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&zero});r.call(bodyTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
  r.call(requirementScroll,"set_viewport",{"UnityEngine.RectTransform"},{view});r.call(requirementScroll,"set_content",{"UnityEngine.RectTransform"},{bodyTr});r.call(requirementScroll,"set_horizontal",{"System.Boolean"},{&no});r.call(requirementScroll,"set_vertical",{"System.Boolean"},{&yes});
  int clamped=2;r.call(requirementScroll,"set_movementType",{"UnityEngine.UI.ScrollRect.MovementType"},{&clamped});syncRequirementScroll(r);
  PMDiagnosticsWrite("Unlock details native scroll ready: independent left-aligned body");
 }catch(const std::exception&e){
  // Optional enhancement failure retains the stock native text and dialog.
  try{clearRequirementScroll(r);}catch(...){}
  logf("Unlock details scroll setup failed; native dialog retained: %s",e.what());
 }
}
void requestRequirementFallback(Runtime&r,NSString*text){
 requirementPopupText=[text copy];requirementPopupSince=NSDate.timeIntervalSinceReferenceDate;requirementFallbackPending=true;
 P task=r.stat(r.klass("PhigrosUI"),"ShowOkMessageBox",{"System.String","System.String"},{r.managedString(@"\u89e3\u9501\u6761\u4ef6"),r.managedString(text)});if(task)requirementTask=r.gchandle_new(task,false);
}
void pollRequirementDialog(Runtime&r){
 if(!requirementPopup&&requirementFallbackPending){
  P dialogs=r.stat(r.type("UnityEngine","Object"),"FindObjectsOfType",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("Phigros.UI","MsgBox")))});
  for(uintptr_t i=0;dialogs&&i<r.array_length(dialogs);++i){P dialog=r.arrayAt(dialogs,int(i));if(r.alive(dialog)&&r.get<bool>(dialog,"isShowing")&&[r.string(r.call(dialog,"get_Content"))isEqualToString:requirementPopupText]){requirementPopup=r.gchandle_new(dialog,false);requirementSeenShowing=true;requirementFallbackPending=false;break;}}
  if(!requirementPopup&&NSDate.timeIntervalSinceReferenceDate-requirementPopupSince>2){logf("Unlock details fallback did not appear; restoring selector input");releaseRequirementDialog(r);}return;
 }
 if(!requirementPopup)return;P popup=target(r,requirementPopup);
 if(!r.alive(popup)){releaseRequirementDialog(r);return;}
 if(!r.get<bool>(popup,"isShowing")){
  if(requirementSeenShowing||!requirementScrollPending){releaseRequirementDialog(r);return;}
  if(NSDate.timeIntervalSinceReferenceDate-requirementPopupSince>2){
   NSString*text=requirementPopupText;try{r.call(popup,"Cancel");}catch(...){}releaseRequirementDialog(r);
   PMDiagnosticsWrite("Unlock details Show timeout; requesting stock info dialog");requestRequirementFallback(r,text?:@"");
  }return;
 }
 requirementSeenShowing=true;
 if(requirementScrollPending){requirementScrollPending=false;prepareRequirementScroll(r,popup);}
 else if(requirementView)try{sizeRequirementDialog(r,popup);syncRequirementScroll(r);}catch(const std::exception&e){logf("Unlock details layout refresh: %s",e.what());try{clearRequirementScroll(r);}catch(...){}}
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
  sizeRequirementDialog(r,popup);
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
 acquireRequirementInput(r,owner);
 try{openRequirementPopup(r,lockUIDetails);}catch(const std::exception&e){
  logf("Unlock details custom popup failed; requesting stock info dialog: %s",e.what());
  try{requestRequirementFallback(r,lockUIDetails);}catch(...){releaseRequirementDialog(r);releaseRequirementInput(r);throw;}
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
