// Sprite-local mesh shear; never mutate the shared skin/native Sprite.
struct SkewMesh{uint32_t renderer=0,source=0,sprite=0,vertices=0,triangles=0;std::vector<V2>base;float slope=0;};
std::map<P,SkewMesh>skewMeshes;
void releaseSkew(Runtime&r,SkewMesh&m){
 try{P renderer=target(r,m.renderer),sprite=target(r,m.sprite),source=target(r,m.source);
  if(r.alive(renderer)&&r.call(renderer,"get_sprite")==sprite&&r.alive(source))r.call(renderer,"set_sprite",{"UnityEngine.Sprite"},{source});
  if(r.alive(sprite))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{sprite});
 }catch(...){}
 for(uint32_t root:{m.renderer,m.source,m.sprite,m.vertices,m.triangles})if(root)r.gchandle_free(root);m=SkewMesh{};
}
void clearSkew(Runtime&r){for(auto&entry:skewMeshes)releaseSkew(r,entry.second);skewMeshes.clear();}
void applySkew(Runtime&r,P renderer,float slope){
 if(!r.alive(renderer))return;auto found=skewMeshes.find(renderer);
 if(std::fabs(slope)<.00001f){if(found!=skewMeshes.end()){releaseSkew(r,found->second);skewMeshes.erase(found);}return;}
 P current=r.call(renderer,"get_sprite");if(!r.alive(current))return;
 if(found!=skewMeshes.end()&&current!=target(r,found->second.sprite)&&current!=target(r,found->second.source)){releaseSkew(r,found->second);skewMeshes.erase(found);found=skewMeshes.end();}
 if(found==skewMeshes.end()){
  SkewMesh m;m.renderer=r.gchandle_new(renderer,false);m.source=r.gchandle_new(current,false);
  try{
   P clone=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object"},{current});m.sprite=r.gchandle_new(clone,false);
   P vertices=r.call(current,"get_vertices"),triangles=r.call(current,"get_triangles");m.vertices=r.gchandle_new(vertices,false);m.triangles=r.gchandle_new(triangles,false);
   for(uintptr_t i=0;i<r.array_length(vertices);++i)m.base.push_back(r.unbox<V2>(r.arrayAt(vertices,int(i))));
   if(m.base.empty()||m.base.size()>65535)throw std::runtime_error("Invalid note sprite geometry");
   found=skewMeshes.emplace(renderer,std::move(m)).first;
  }catch(...){releaseSkew(r,m);throw;}
 }
 auto&m=found->second;P clone=target(r,m.sprite);
 if(m.slope!=slope){P vertices=target(r,m.vertices);
  for(size_t i=0;i<m.base.size();++i){V2 vertex=m.base[i];vertex.x+=slope*vertex.y;P boxed=r.value_box(r.type("UnityEngine","Vector2"),&vertex);uint32_t root=r.gchandle_new(boxed,false);int index=int(i);
   try{r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),vertices,{boxed,&index});}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
  }
  r.call(clone,"OverrideGeometry",{"UnityEngine.Vector2[]","System.UInt16[]"},{vertices,target(r,m.triangles)});m.slope=slope;
 }
 if(r.call(renderer,"get_sprite")!=clone)r.call(renderer,"set_sprite",{"UnityEngine.Sprite"},{clone});
}
