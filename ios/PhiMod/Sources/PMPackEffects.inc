// Resource-pack runtime: uses native effect/sound calls, never score callbacks.
struct PackEffect{uint32_t go=0,source=0;P renderer=nullptr;double start=0;int frame=-1;};
std::vector<PackEffect>packEffects;std::vector<P>packFrames;
std::map<int,uint32_t>packClips;uint32_t packAudioSource=0;
struct PackLine{uint32_t renderer,original;};std::map<P,PackLine>packLines;
float packFxDuration=.5f,packFxScale=1;bool packFxRotate=false,packFxTinted=true;
Color packPerfect{1,.925f,.627f,1},packGood{.706f,.882f,1,1};
P packGoodPrefab=nullptr,packPerfectPrefab=nullptr;
void clearPackExtras(Runtime&r){
 for(auto&e:packEffects){P go=target(r,e.go);if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(e.go);r.gchandle_free(e.source);}packEffects.clear();packFrames.clear();
 for(auto&entry:packLines){P renderer=target(r,entry.second.renderer),original=target(r,entry.second.original);if(r.alive(renderer)&&r.alive(original))r.call(renderer,"set_sprite",{"UnityEngine.Sprite"},{original});r.gchandle_free(entry.second.renderer);r.gchandle_free(entry.second.original);}packLines.clear();
 packClips.clear();packAudioSource=0;packGoodPrefab=packPerfectPrefab=nullptr;
}
void preparePackExtras(Runtime&r,const std::map<std::string,std::string>&meta){
 auto value=[&](const char*key,float fallback){auto it=meta.find(key);if(it==meta.end())return fallback;try{float v=std::stof(it->second);return std::isfinite(v)?v:fallback;}catch(...){return fallback;}};
 auto flag=[&](const char*key,bool fallback){auto it=meta.find(key);return it==meta.end()?fallback:it->second.find("true")!=std::string::npos;};
 auto tint=[&](const char*key,Color fallback){auto it=meta.find(key);if(it==meta.end())return fallback;try{unsigned long rgb=std::stoul(it->second,nullptr,0);return Color{float((rgb>>16)&255)/255,float((rgb>>8)&255)/255,float(rgb&255)/255,1};}catch(...){return fallback;}};
 packFxDuration=std::clamp(value("hitFxDuration",.5f),.1f,2.f);packFxScale=std::clamp(value("hitFxScale",1.f),.05f,10.f);packFxRotate=flag("hitFxRotate",false);packFxTinted=flag("hitFxTinted",true);packPerfect=tint("colorPerfect",{1,.925f,.627f,1});packGood=tint("colorGood",{.706f,.882f,1,1});
 NSString*folder=[NSString stringWithUTF8String:skinFolder.c_str()];NSString*fx=findFile(folder,@"hit_fx.png");if(fx){if(skinCols*skinRows>1024)throw std::runtime_error("Skin hit effect exceeds 1024 frames");for(int i=0;i<skinCols*skinRows;++i)packFrames.push_back(skinSprite(r,fx,100+i));}
 NSString*line=findFile(folder,@"line.png");if(line){skinFiles["line.png"]=line;loadTexture(r,line);}
 for(auto&entry:std::vector<std::pair<int,const char*>>{{7,"click"},{8,"drag"},{9,"flick"}}){NSString*kind=[NSString stringWithUTF8String:entry.second];NSString*path=[folder stringByAppendingPathComponent:[kind stringByAppendingString:@".m4a"]];
  if(![NSFileManager.defaultManager fileExistsAtPath:path])for(NSString*ext in @[@"wav",@"ogg",@"mp3",@"flac"]){NSString*input=[folder stringByAppendingPathComponent:[kind stringByAppendingFormat:@".%@",ext]];if([NSFileManager.defaultManager fileExistsAtPath:input]){NSError*error=nil;if(!PMConvertAudioResource(input,path,&error))logf("Skin sound conversion failed: %s",error.localizedDescription.UTF8String);break;}}
  if([NSFileManager.defaultManager fileExistsAtPath:path]){P clip=pmcontent::loadSkinAudio(r,path);keep(r,clip);packClips[entry.first]=roots.back();}
 }
 P level=target(r,videoLevel);if(r.alive(level)){packGoodPrefab=r.get<P>(level,"goodJudge");packPerfectPrefab=r.get<P>(level,"perfectJudge");}
 logf("Resource pack extras ready frames=%lu sounds=%lu line=%d",(unsigned long)packFrames.size(),(unsigned long)packClips.size(),skinFiles.count("line.png")!=0);
}
void updatePackEffects(Runtime&r){
 double now=r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_time"));
 for(auto it=packEffects.begin();it!=packEffects.end();){P go=target(r,it->go);int frame=int((now-it->start)/packFxDuration*packFrames.size());
  if(!r.alive(go)||frame>=(int)packFrames.size()){if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(it->go);r.gchandle_free(it->source);it=packEffects.erase(it);continue;}
  P source=target(r,it->source);if(r.alive(source)){P from=r.call(source,"get_transform"),to=r.call(go,"get_transform");V3 pos=r.unbox<V3>(r.call(from,"get_position"));r.call(to,"set_position",{"UnityEngine.Vector3"},{&pos});}
  frame=std::max(0,frame);if(it->frame!=frame){r.call(it->renderer,"set_sprite",{"UnityEngine.Sprite"},{packFrames[frame]});it->frame=frame;}++it;
 }
}
