// Included in PMContentRuntime's helper namespace after track evaluators.
// Android rpe_hud.inc: wrap native HUD so native text/progress updates continue.
struct HudGraphic{uint32_t root=0;Color original{},last{};bool applied=false;};
struct HudBinding{
 uint32_t wrapper=0,element=0,parent=0;P transform=nullptr,group=nullptr;bool captured=false;
 V3 origin{},scale{},rotation{},clipOrigin{};V2 anchorMin{},anchorMax{},pivot{},size{},anchored{};
 int sibling=0;float alpha=1;std::vector<HudGraphic>graphics;
};
struct HudClip{uint32_t root=0;P tr=nullptr;V3 origin{};};
std::map<P,HudClip>hudClips;
P newHudRect(Runtime&r,const char*name,uint32_t&root){
 P go=r.object_new(r.type("UnityEngine","GameObject"));root=r.gchandle_new(go,false);
 P types=r.array_new(r.type("System","Type"),1);uint32_t typesRoot=r.gchandle_new(types,false);int zero=0;
 try{r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),types,{r.type_get_object(r.class_get_type(r.type("UnityEngine","RectTransform"))),&zero});r.call(go,".ctor",{"System.String","System.Type[]"},{r.string_new(name),types});}
 catch(...){r.gchandle_free(typesRoot);r.gchandle_free(root);root=0;throw;}r.gchandle_free(typesRoot);return go;
}
HudClip&hudClip(Runtime&r,P parent){
 auto found=hudClips.find(parent);if(found!=hudClips.end())return found->second;
 P camera=r.stat(r.type("UnityEngine","Camera"),"get_main");if(!r.alive(camera))throw std::runtime_error("HUD clipping camera missing");
 V3 cam=r.unbox<V3>(r.call(r.call(camera,"get_transform"),"get_position"));
 float height=2*r.unbox<float>(r.call(camera,"get_orthographicSize")),width=height*std::min(16.f/9.f,r.unbox<float>(r.call(camera,"get_aspect")));
 V3 lower{cam.x-width/2,cam.y-height/2,0},upper{cam.x+width/2,cam.y+height/2,0},center{cam.x,cam.y,0};
 lower=r.unbox<V3>(r.call(parent,"InverseTransformPoint",{"UnityEngine.Vector3"},{&lower}));upper=r.unbox<V3>(r.call(parent,"InverseTransformPoint",{"UnityEngine.Vector3"},{&upper}));center=r.unbox<V3>(r.call(parent,"InverseTransformPoint",{"UnityEngine.Vector3"},{&center}));
 HudClip clip;P go=newHudRect(r,"PhiMod_RPE_HUD_Viewport",clip.root);
 try{
  clip.tr=r.call(go,"get_transform");clip.origin=center;bool no=false;V2 mid{.5f,.5f},size{std::fabs(upper.x-lower.x),std::fabs(upper.y-lower.y)};
  r.call(clip.tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});
  r.call(clip.tr,"set_anchorMin",{"UnityEngine.Vector2"},{&mid});r.call(clip.tr,"set_anchorMax",{"UnityEngine.Vector2"},{&mid});r.call(clip.tr,"set_pivot",{"UnityEngine.Vector2"},{&mid});r.call(clip.tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(clip.tr,"set_localPosition",{"UnityEngine.Vector3"},{&center});
  r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine.UI","RectMask2D")))});
 }catch(...){r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(clip.root);throw;}
 return hudClips.emplace(parent,clip).first->second;
}
std::map<int,HudBinding>hudBindings;std::set<int>hudErrors;
void releaseHudBinding(Runtime&r,HudBinding&h){
 P element=target(r,h.element),parent=target(r,h.parent),wrapper=target(r,h.wrapper);
 try{
  if(h.captured&&r.alive(element)&&r.alive(parent)){
   P tr=r.call(element,"get_transform");bool no=false;r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});
   r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&h.anchorMin});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&h.anchorMax});r.call(tr,"set_pivot",{"UnityEngine.Vector2"},{&h.pivot});
   r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&h.size});r.call(tr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&h.anchored});
   r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&h.scale});r.call(tr,"set_localEulerAngles",{"UnityEngine.Vector3"},{&h.rotation});r.call(tr,"SetSiblingIndex",{"System.Int32"},{&h.sibling});
  }
  for(auto&g:h.graphics){P graphic=target(r,g.root);if(r.alive(graphic)){Color c=r.unbox<Color>(r.call(graphic,"get_color"));c.r=g.original.r;c.g=g.original.g;c.b=g.original.b;r.call(graphic,"set_color",{"UnityEngine.Color"},{&c});}}
  if(r.alive(wrapper))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{wrapper});
 }catch(const std::exception&e){log([NSString stringWithFormat:@"RPE HUD restore failed: %s",e.what()]);}
 for(auto&g:h.graphics)if(g.root)r.gchandle_free(g.root);
 for(uint32_t root:{h.wrapper,h.element,h.parent})if(root)r.gchandle_free(root);
 h=HudBinding{};
}
void clearHud(Runtime&r){
 for(auto&entry:hudBindings)releaseHudBinding(r,entry.second);
 hudBindings.clear();for(auto&entry:hudClips){P go=target(r,entry.second.root);try{if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});}catch(...){}r.gchandle_free(entry.second.root);}hudClips.clear();hudLines.clear();hudErrors.clear();if(hudLevel)r.gchandle_free(hudLevel);hudLevel=0;
}
void bindHud(Runtime&r,HudBinding&h,int code){
 P level=target(r,hudLevel);if(!r.alive(level))return;
 const char*fields[]={"pause","combo","comboText","score","progressBar","songsName","songsLevel"};
 P ui=r.get<P>(level,"levelUICont"),element=ui?r.get<P>(ui,fields[code-1]):nullptr;if(!r.alive(element))return;
 P tr=r.call(element,"get_transform"),parent=r.call(tr,"get_parent");if(!r.alive(parent))return;
 try{
  h.element=r.gchandle_new(element,false);h.parent=r.gchandle_new(parent,false);
  h.origin=r.unbox<V3>(r.call(tr,"get_localPosition"));h.scale=r.unbox<V3>(r.call(tr,"get_localScale"));h.rotation=r.unbox<V3>(r.call(tr,"get_localEulerAngles"));h.sibling=r.unbox<int>(r.call(tr,"GetSiblingIndex"));
  h.anchorMin=r.unbox<V2>(r.call(tr,"get_anchorMin"));h.anchorMax=r.unbox<V2>(r.call(tr,"get_anchorMax"));h.pivot=r.unbox<V2>(r.call(tr,"get_pivot"));h.size=r.unbox<V2>(r.call(tr,"get_sizeDelta"));h.anchored=r.unbox<V2>(r.call(tr,"get_anchoredPosition"));h.captured=true;
  P go=newHudRect(r,"PhiMod_RPE_HUD",h.wrapper);
  int layer=r.unbox<int>(r.call(element,"get_layer"));r.call(go,"set_layer",{"System.Int32"},{&layer});
  h.transform=r.call(go,"get_transform");bool no=false;auto&clip=hudClip(r,parent);h.clipOrigin=clip.origin;
  r.call(h.transform,"SetParent",{"UnityEngine.Transform","System.Boolean"},{clip.tr,&no});
  V2 mid{.5f,.5f},pivot=r.unbox<V2>(r.call(parent,"get_pivot"));Rect parentRect=r.unbox<Rect>(r.call(parent,"get_rect"));V2 size{parentRect.w,parentRect.h};
  V3 origin{-clip.origin.x,-clip.origin.y,-clip.origin.z},one{1,1,1};
  // Keep the wrapper's rect identical to the authored parent, even though the
  // clipping ancestor is narrower on letterboxed displays.
  r.call(h.transform,"set_anchorMin",{"UnityEngine.Vector2"},{&mid});r.call(h.transform,"set_anchorMax",{"UnityEngine.Vector2"},{&mid});r.call(h.transform,"set_pivot",{"UnityEngine.Vector2"},{&pivot});r.call(h.transform,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
  r.call(h.transform,"set_localPosition",{"UnityEngine.Vector3"},{&origin});r.call(h.transform,"set_localScale",{"UnityEngine.Vector3"},{&one});
  r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{h.transform,&no});
  h.group=r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine","CanvasGroup")))});
  P graphics=r.children(element,r.type("UnityEngine.UI","Graphic"));for(uintptr_t i=0;graphics&&i<r.array_length(graphics);++i){P graphic=r.arrayAt(graphics,int(i));Color color=r.unbox<Color>(r.call(graphic,"get_color"));h.graphics.push_back({r.gchandle_new(graphic,false),color,color,false});}
  log([NSString stringWithFormat:@"RPE HUD bound: code=%d target=%s",code,fields[code-1]]);
 }catch(...){releaseHudBinding(r,h);throw;}
}
void updateHud(Runtime&r,int code,P line,NSDictionary*source,float now){
 if(code<1||code>7)return;
 auto&h=hudBindings[code];if(!h.wrapper)bindHud(r,h,code);if(!h.wrapper)return;
 P element=target(r,h.element),parent=target(r,h.parent);if(!r.alive(element)||!r.alive(parent))return;
 NSDictionary*d=source[@"pmDecor"];
 V3 scale{(float)trackValue(d[@"scaleXEvents"],now,1),(float)trackValue(d[@"scaleYEvents"],now,1),1};
 V3 motion=r.unbox<V3>(r.call(r.call(line,"get_transform"),"get_position"));motion.z=0;
 motion=r.unbox<V3>(r.call(parent,"InverseTransformVector",{"UnityEngine.Vector3"},{&motion}));
 // Use the engine's pose, already including converted parent motion/rotation.
 float angle=r.get<float>(line,"theta");
 P child=r.call(element,"get_transform");V3 origin=r.unbox<V3>(r.call(child,"get_localPosition"));
 auto offset=pmHudOffset(origin.x,origin.y,motion.x,motion.y,scale.x,scale.y,angle);
 V3 position{offset.x-h.clipOrigin.x,offset.y-h.clipOrigin.y,-h.clipOrigin.z},rotation{0,0,angle};
 r.call(h.transform,"set_localScale",{"UnityEngine.Vector3"},{&scale});r.call(h.transform,"set_localEulerAngles",{"UnityEngine.Vector3"},{&rotation});r.call(h.transform,"set_localPosition",{"UnityEngine.Vector3"},{&position});
 h.alpha=sourceLineAlpha(source[@"judgeLineDisappearEvents"],now,scalar(source[@"bpm"],120));
 r.call(h.group,"set_alpha",{"System.Single"},{&h.alpha});
 bool interact=h.alpha>.001f&&std::fabs(scale.x)>.00001f&&std::fabs(scale.y)>.00001f;
 r.call(h.group,"set_interactable",{"System.Boolean"},{&interact});r.call(h.group,"set_blocksRaycasts",{"System.Boolean"},{&interact});
 NSArray*colors=d[@"colorEvents"];Color multiplier{1,1,1,1};if(colors.count){multiplier.r=trackValue(colors,now,1,0);multiplier.g=trackValue(colors,now,1,1);multiplier.b=trackValue(colors,now,1,2);}
 for(auto&g:h.graphics){P graphic=target(r,g.root);if(!r.alive(graphic))continue;Color color=r.unbox<Color>(r.call(graphic,"get_color"));
  Color next=color;next.r=g.original.r*multiplier.r;next.g=g.original.g*multiplier.g;next.b=g.original.b*multiplier.b;
  if(next.r!=color.r||next.g!=color.g||next.b!=color.b)r.call(graphic,"set_color",{"UnityEngine.Color"},{&next});g.last=next;g.applied=true;
 }
}

void validateHud(Runtime&r){
 P ui=r.klass("LevelUICont");for(const char*field:{"pause","combo","comboText","score","progressBar","songsName","songsLevel"})r.field(ui,field,"UnityEngine.GameObject",false);
 r.field(r.klass("LevelControl"),"levelUICont","LevelUICont",false);
 r.resolve(r.klass("JudgeControl"),"CheckPause",{"System.Int32"});
 r.resolve(r.type("UnityEngine","Transform"),"InverseTransformVector",{"UnityEngine.Vector3"});
 r.resolve(r.type("UnityEngine","Transform"),"InverseTransformPoint",{"UnityEngine.Vector3"});
 r.resolve(r.type("UnityEngine","CanvasGroup"),"set_alpha",{"System.Single"});
 r.resolve(r.type("UnityEngine","CanvasGroup"),"set_blocksRaycasts",{"System.Boolean"});
 r.resolve(r.type("UnityEngine","GameObject"),".ctor",{"System.String","System.Type[]"});
}
