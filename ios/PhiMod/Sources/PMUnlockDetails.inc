// Native button + native MsgBox with a scrollable body. No save-sync callbacks.
uint32_t requirementRoot=0,requirementPopup=0;P requirementButton=nullptr;
void clearRequirementUI(Runtime&r){
 if(requirementPopup){P popup=target(r,requirementPopup);if(r.alive(popup))try{r.call(popup,"Cancel");}catch(...){}r.gchandle_free(requirementPopup);requirementPopup=0;}
 if(requirementRoot){P go=target(r,requirementRoot);if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(requirementRoot);requirementRoot=0;}requirementButton=nullptr;
}
void showRequirementButton(Runtime&r,P tip,bool visible){
 if(visible&&!requirementRoot){
  P selector=target(r,lockUIOwner);if(!r.alive(selector)||!r.alive(tip))return;
  P source=r.get<P>(selector,"startButton"),challenge=r.get<P>(selector,"challengeSongSelectorControl");if(r.alive(challenge)){P select=r.get<P>(challenge,"selectButton");if(r.alive(select))source=select;}
  P tipTr=r.call(tip,"get_transform"),parent=r.call(tipTr,"get_parent");bool no=false;
  P clone=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},{r.call(source,"get_gameObject"),parent,&no});requirementRoot=r.gchandle_new(clone,false);
  requirementButton=r.component(clone,r.type("UnityEngine.UI","Button"));
  P animators=r.children(clone,r.type("UnityEngine","Animator"));for(uintptr_t i=0;animators&&i<r.array_length(animators);++i)r.call(r.arrayAt(animators,int(i)),"set_enabled",{"System.Boolean"},{&no});
  P evt=r.object_new(r.nested(r.type("UnityEngine.UI","Button"),"ButtonClickedEvent"));uint32_t root=r.gchandle_new(evt,false);
  try{r.call(evt,".ctor");r.call(requirementButton,"set_onClick",{"UnityEngine.UI.Button.ButtonClickedEvent"},{evt});}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
  P labels=r.children(clone,r.type("UnityEngine.UI","Text"));for(uintptr_t i=0;labels&&i<r.array_length(labels);++i){P label=r.arrayAt(labels,int(i));r.call(label,"set_text",{"System.String"},{r.managedString(i?@"":@"\u67e5\u770b\u89e3\u9501\u8981\u6c42")});int font=24;r.call(label,"set_fontSize",{"System.Int32"},{&font});r.call(label,"set_resizeTextForBestFit",{"System.Boolean"},{&no});}
 }
 P go=target(r,requirementRoot);if(!r.alive(go))return;
 if(visible){P tipTr=r.call(tip,"get_transform"),tr=r.call(go,"get_transform");
  for(const char*field:{"anchorMin","anchorMax","pivot","sizeDelta","anchoredPosition"}){std::string get=std::string("get_")+field,set=std::string("set_")+field;TipSize value=r.unbox<TipSize>(r.call(tipTr,get.c_str()));if(!strcmp(field,"sizeDelta"))value.y=std::max(value.y,48.f);r.call(tr,set.c_str(),{"UnityEngine.Vector2"},{&value});}
  struct V3{float x,y,z;};V3 one{1,1,1};r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&one});bool yes=true;r.call(requirementButton,"set_interactable",{"System.Boolean"},{&yes});
 }
 lockActive(r,go,visible);
 // The cloned button supplies the visible caption while the original Text
 // remains available for fit measurement and automatic short-text restoration.
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
