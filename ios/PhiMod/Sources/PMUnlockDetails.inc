// Native button + native MsgBox with a scrollable body. No save-sync callbacks.
uint32_t requirementRoot=0,requirementPopup=0;P requirementButton=nullptr;
void clearRequirementUI(Runtime&r){
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
 if(visible&&!requirementRoot){
  if(!r.alive(tip))return;P parent=r.call(r.call(tip,"get_transform"),"get_parent");
  P object=requirementObject(r,"PhiMod Unlock Details",parent);requirementRoot=r.gchandle_new(object,false);
  try{
   P rect=r.call(object,"get_transform"),image=requirementComponent(r,object,"UnityEngine.UI","Image");
   // Clean light button, like the native selector's actions, without copying
   // their sprite atlas crop or stretching a full Start-button hierarchy.
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
   PMDiagnosticsWrite("Unlock details independent native button ready");
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
  r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(rect,"set_localScale",{"UnityEngine.Vector3"},{&one});r.call(rect,"set_position",{"UnityEngine.Vector3"},{&world});r.call(rect,"SetAsLastSibling");
 }
 lockActive(r,object,visible);
 if(tip){bool enabled=!visible;r.call(tip,"set_enabled",{"System.Boolean"},{&enabled});}
}
void openRequirementPopup(Runtime&r,NSString*text){
 if(requirementPopup){P prior=target(r,requirementPopup);if(r.alive(prior)&&r.get<bool>(prior,"isShowing"))return;r.gchandle_free(requirementPopup);requirementPopup=0;}
 bool no=false,yes=true;
 P popup=r.stat(r.klass("PhigrosUI"),"CreateMessageBox",{"System.String","System.String","System.Boolean"},{r.managedString(@"\u89e3\u9501\u8981\u6c42"),r.managedString(text),&no});
 if(!r.alive(popup))throw std::runtime_error("Native message box not created");requirementPopup=r.gchandle_new(popup,false);
 try{
  TipSize box{1000,660};r.call(popup,"set_Size",{"UnityEngine.Vector2"},{&box});r.call(popup,"Show");r.call(popup,"RefreshElements");
  P content=r.get<P>(popup,"content"),oldTr=r.call(content,"get_rectTransform"),parent=r.call(oldTr,"get_parent");
  int font=28,wrap=0,overflow=1,align=0;r.call(content,"set_fontSize",{"System.Int32"},{&font});r.call(content,"set_resizeTextForBestFit",{"System.Boolean"},{&no});r.call(content,"set_supportRichText",{"System.Boolean"},{&no});r.call(content,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&wrap});r.call(content,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&overflow});r.call(content,"set_alignment",{"UnityEngine.TextAnchor"},{&align});r.call(content,"set_raycastTarget",{"System.Boolean"},{&yes});
  P go=r.object_new(r.type("UnityEngine","GameObject"));uint32_t temporary=r.gchandle_new(go,false);
  try{
   P types=r.array_new(r.type("System","Type"),1);uint32_t typesRoot=r.gchandle_new(types,false);int zero=0;
   try{r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),types,{r.type_get_object(r.class_get_type(r.type("UnityEngine","RectTransform"))),&zero});r.call(go,".ctor",{"System.String","System.Type[]"},{r.string_new("PhiMod Unlock Scroll"),types});}catch(...){r.gchandle_free(typesRoot);throw;}r.gchandle_free(typesRoot);
   int layer=r.unbox<int>(r.call(r.call(content,"get_gameObject"),"get_layer"));r.call(go,"set_layer",{"System.Int32"},{&layer});
   P view=r.call(go,"get_transform");r.call(view,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});
   for(const char*field:{"anchorMin","anchorMax","pivot","sizeDelta","anchoredPosition"}){std::string get=std::string("get_")+field,set=std::string("set_")+field;TipSize value=r.unbox<TipSize>(r.call(oldTr,get.c_str()));r.call(view,set.c_str(),{"UnityEngine.Vector2"},{&value});}
   r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine.UI","RectMask2D")))});
   P image=r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine.UI","Image")))});TipColor transparent{0,0,0,0};r.call(image,"set_color",{"UnityEngine.Color"},{&transparent});r.call(image,"set_raycastTarget",{"System.Boolean"},{&yes});
   P scroll=r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine.UI","ScrollRect")))});
   r.call(oldTr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{view,&no});TipSize low{0,1},high{1,1},pivot{.5f,1},position{0,0};r.call(oldTr,"set_anchorMin",{"UnityEngine.Vector2"},{&low});r.call(oldTr,"set_anchorMax",{"UnityEngine.Vector2"},{&high});r.call(oldTr,"set_pivot",{"UnityEngine.Vector2"},{&pivot});r.call(oldTr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&position});
   TipSize size{0,32};r.call(oldTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});float height=r.unbox<float>(r.call(content,"get_preferredHeight"));size.y=std::max(32.f,height+24);r.call(oldTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
   r.call(scroll,"set_viewport",{"UnityEngine.RectTransform"},{view});r.call(scroll,"set_content",{"UnityEngine.RectTransform"},{oldTr});r.call(scroll,"set_horizontal",{"System.Boolean"},{&no});r.call(scroll,"set_vertical",{"System.Boolean"},{&yes});int clamped=2;r.call(scroll,"set_movementType",{"UnityEngine.UI.ScrollRect.MovementType"},{&clamped});float top=1;r.call(scroll,"set_verticalNormalizedPosition",{"System.Single"},{&top});
  }catch(...){r.gchandle_free(temporary);throw;}r.gchandle_free(temporary);
 }catch(...){try{r.call(popup,"Cancel");}catch(...){}r.gchandle_free(requirementPopup);requirementPopup=0;throw;}
}
