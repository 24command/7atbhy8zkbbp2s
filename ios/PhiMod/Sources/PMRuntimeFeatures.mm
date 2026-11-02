#include "PMRuntimeFeatures.hpp"
#include "PMContentRuntime.hpp"
#include "../Core/PMRPEGeometry.hpp"
#include <array>
#include "../Core/PMLegacyCore.hpp"
#import "PMSettings.h"
#import "PMContentStore.h"
#import "PMExtensionTracks.h"
#import "PMMetalShaders.h"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cmath>
#include <climits>
#include <fstream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace pmfeatures {
using pmbridge::P;
void attach(pmbridge::Runtime&) {}

using pmbridge::Runtime;
struct V2 { float x,y; };
struct V3 { float x,y,z; };
struct Rect { float x,y,w,h; };
struct Bounds { V3 center,extents; };
struct Color { float r,g,b,a; };
namespace {
std::string skinFolder;
std::map<std::string,NSString*>skinFiles;std::set<int>skinAppliedTypes;std::set<std::string>skinErrors;
std::map<std::string,uint32_t> skinTextures,skinSprites;
std::map<std::string,double>skinAtlasYScale,skinSourceWidths;
std::map<std::string,float>skinNormalWorldWidths;
std::vector<uint32_t> roots;
std::map<P,std::pair<float,float>> holdBases;
std::map<P,std::array<P,3>> holdOriginalParts;
bool skinHoldCompact=false;
int skinHead=50,skinTail=50,skinHeadMH=50,skinTailMH=50,skinCols=5,skinRows=6;
std::set<int>skinBoundTypes;bool skinReady=false;std::map<P,P>skinBoundNotes;std::map<P,bool>skinHighlights;std::map<P,P>skinOriginals;std::map<P,uint32_t>skinOriginalRoots;
struct TrackEvent { double s=0,e=0,a=0,b=0; };
struct Video { int index=0; double start=0; std::string scale,path; std::map<std::string,std::vector<TrackEvent>> tracks; uint32_t go=0,texture=0; P player=nullptr,raw=nullptr; bool begun=false,failed=false; };
std::vector<Video> videos;
uint32_t videoLevel=0;
bool legacyActive=false; int legacyStep=-1,legacyJudge=-1; std::string legacyFace;
void logf(const char *fmt,...){char b[768];va_list ap;va_start(ap,fmt);vsnprintf(b,sizeof(b),fmt,ap);va_end(ap);PMDiagnosticsWrite(b);}
P target(Runtime&r,uint32_t h){return h?r.gchandle_get_target(h):nullptr;}
void keep(Runtime&r,P p){if(p)roots.push_back(r.gchandle_new(p,false));}
std::string readText(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f)return {};std::ostringstream s;s<<f.rdbuf();return s.str();}
std::string hexDecode(const std::string&s){if(s.size()%2)return {};std::string out;out.reserve(s.size()/2);for(size_t i=0;i<s.size();i+=2){unsigned v=0;try{v=std::stoul(s.substr(i,2),nullptr,16);}catch(...){return {};}out.push_back(char(v));}return out;}
NSString *findFile(NSString *root,NSString *name){NSFileManager*fm=NSFileManager.defaultManager;NSString*direct=[root stringByAppendingPathComponent:name];if([fm fileExistsAtPath:direct])return direct;NSDirectoryEnumerator*e=[fm enumeratorAtPath:root];for(NSString*rel in e)if([rel.lastPathComponent.lowercaseString isEqualToString:name.lowercaseString])return [root stringByAppendingPathComponent:rel];return nil;}
std::pair<int,int> pairValue(const std::map<std::string,std::string>&m,const char*key,int a,int b){auto i=m.find(key);if(i==m.end())return {a,b};std::regex re("[0-9]+");std::sregex_iterator it(i->second.begin(),i->second.end(),re),end;if(it==end)return {a,b};try{a=std::stoi((*it)[0]);++it;if(it!=end)b=std::stoi((*it)[0]);}catch(...){}return {std::clamp(a,0,4096),std::clamp(b,0,4096)};}
std::map<std::string,std::string> yaml(NSString*path){std::map<std::string,std::string> out;if(!path)return out;NSString*t=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];for(NSString*line in [t componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSRange q=[line rangeOfString:@":"];if(q.location==NSNotFound)continue;NSString*k=[[line substringToIndex:q.location]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSString*v=[[line substringFromIndex:q.location+1]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(k.length&&v.length)out[k.UTF8String]=v.UTF8String;}return out;}
P managedBytes(Runtime&r,NSData*d){if(!d.length||d.length>INT_MAX)throw std::runtime_error("feature byte array invalid");P a=r.array_new(r.type("System","Byte"),d.length);if(!a)throw std::runtime_error("feature byte array allocation failed");uint32_t h=r.gchandle_new(a,false);try{void*ptr=(void*)d.bytes;int zero=0,n=(int)d.length;r.stat(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",{"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,a,&n});r.gchandle_free(h);return a;}catch(...){r.gchandle_free(h);throw;}}
P loadTexture(Runtime&r,NSString*path){
 NSData*d=[NSData dataWithContentsOfFile:path];
 if(!d.length||d.length>64ull*1024*1024)throw std::runtime_error("skin texture missing or over 64 MiB");
 CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)d,(__bridge CFDictionaryRef)@{(NSString*)kCGImageSourceShouldCache:@NO});
 if(!source)throw std::runtime_error("Skin image format could not be decoded");
 NSDictionary*properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
 double sourceW=[properties[(NSString*)kCGImagePropertyPixelWidth] doubleValue],sourceH=[properties[(NSString*)kCGImagePropertyPixelHeight] doubleValue];
 if(!std::isfinite(sourceW)||!std::isfinite(sourceH)||sourceW<=0||sourceH<=0){CFRelease(source);throw std::runtime_error("Invalid skin image dimensions");}
 skinSourceWidths[path.UTF8String]=sourceW;
 double atlasScale=1;
 if(sourceW>4096||sourceH>4096){
  NSDictionary*options=@{(NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(NSString*)kCGImageSourceThumbnailMaxPixelSize:@4096,(NSString*)kCGImageSourceShouldCacheImmediately:@YES};
  CGImageRef thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);
  CFRelease(source);source=nullptr;
  if(!thumbnail)throw std::runtime_error("Skin image downsampling failed");
  size_t width=CGImageGetWidth(thumbnail),height=CGImageGetHeight(thumbnail);
  UIImage*scaled=[UIImage imageWithCGImage:thumbnail];CGImageRelease(thumbnail);
  if(!width||!height||width>4096||height>4096)throw std::runtime_error("Invalid downsampled skin dimensions");
  atlasScale=double(height)/sourceH;d=UIImagePNGRepresentation(scaled);
  if(!d.length||d.length>64ull*1024*1024)throw std::runtime_error("Downsampled skin encoding failed or exceeded limit");
  logf("Skin texture resized %s: %.0fx%.0f -> %lux%lu",path.lastPathComponent.UTF8String,sourceW,sourceH,(unsigned long)width,(unsigned long)height);
 }
 if(source)CFRelease(source);
 P a=managedBytes(r,d);uint32_t ah=r.gchandle_new(a,false);try{P t=r.object_new(r.type("UnityEngine","Texture2D"));if(!t)throw std::runtime_error("skin Texture2D allocation failed");uint32_t th=r.gchandle_new(t,false);try{int w=2,h=2,fmt=4;bool mip=false;r.call(t,".ctor",{"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"},{&w,&h,&fmt,&mip});bool unreadable=true;bool ok=r.unbox<bool>(r.stat(r.type("UnityEngine","ImageConversion"),"LoadImage",{"UnityEngine.Texture2D","System.Byte[]","System.Boolean"},{t,a,&unreadable}));if(!ok)throw std::runtime_error("skin ImageConversion failed");int flags=32;r.call(t,"set_hideFlags",{"UnityEngine.HideFlags"},{&flags});skinTextures[path.UTF8String]=th;skinAtlasYScale[path.UTF8String]=atlasScale;roots.push_back(th);r.gchandle_free(ah);return t;}catch(...){r.gchandle_free(th);throw;}}catch(...){r.gchandle_free(ah);throw;}}
P skinSprite(Runtime&r,NSString*file,int part,P original=nullptr){NSString*key=[NSString stringWithFormat:@"%@/%d/%p",file,part,original];auto hit=skinSprites.find(key.UTF8String);if(hit!=skinSprites.end())return target(r,hit->second);auto th=skinTextures.find(file.UTF8String);P texture=th==skinTextures.end()?nullptr:target(r,th->second);if(!r.alive(texture))throw std::runtime_error("Skin texture native object was unloaded");int w=r.unbox<int>(r.call(texture,"get_width")),h=r.unbox<int>(r.call(texture,"get_height"));Rect rect{0,0,(float)w,(float)h};V2 pivot{.5f,.5f};float ppu=100.f,worldWidth=1.5f;if(original){try{Rect old=r.unbox<Rect>(r.call(original,"get_rect"));float oldPpu=r.unbox<float>(r.call(original,"get_pixelsPerUnit"));worldWidth=oldPpu>0?old.w/oldPpu:1.5f;pivot=r.unbox<V2>(r.call(original,"get_pivot"));pivot={old.w>0?pivot.x/old.w:.5f,old.h>0?pivot.y/old.h:.5f};}catch(...){}}
 if(part>=100){int frame=part-100,cols=std::max(1,skinCols),rows=std::max(1,skinRows);float fw=float(w)/cols,fh=float(h)/rows;rect={float(frame%cols)*fw,float(h-(frame/cols+1)*fh),fw,fh};worldWidth=1.5f;}else if(part>=0){bool mh=[file.lastPathComponent.lowercaseString containsString:@"_mh"];float atlasScale=skinAtlasYScale.count(file.UTF8String)?float(skinAtlasYScale.at(file.UTF8String)):1.f;float head=std::clamp(float(mh?skinHeadMH:skinHead)*atlasScale,0.f,float(h)-.001f),tail=std::clamp(float(mh?skinTailMH:skinTail)*atlasScale,0.f,float(h)-head-.001f);if(part==0)rect={0,0,(float)w,head};else if(part==1)rect={0,head,(float)w,float(h)-head-tail};else rect={0,float(h)-tail,(float)w,tail};}if(rect.w<=0||rect.h<=0)return nullptr;
 if(part<100){
  NSString*name=file.lastPathComponent.lowercaseString;bool mh=[name hasSuffix:@"_mh.png"];
  NSString*normalName=mh?[[name substringToIndex:name.length-7]stringByAppendingString:@".png"]:name;
  std::string widthKey=std::string(normalName.UTF8String)+"/"+std::to_string(part);
  if(!mh)skinNormalWorldWidths.emplace(widthKey,worldWidth);
  else{
   auto normal=skinFiles.find(normalName.UTF8String);auto baseWidth=skinNormalWorldWidths.find(widthKey);
   if(normal!=skinFiles.end()&&baseWidth!=skinNormalWorldWidths.end()){
    auto normalPixels=skinSourceWidths.find(normal->second.UTF8String),highlightPixels=skinSourceWidths.find(file.UTF8String);
    if(normalPixels!=skinSourceWidths.end()&&highlightPixels!=skinSourceWidths.end()&&normalPixels->second>0)
     worldWidth=baseWidth->second*float(highlightPixels->second/normalPixels->second);
   }
  }
 }
 ppu=rect.w/std::max(.001f,worldWidth);P s=r.stat(r.type("UnityEngine","Sprite"),"Create",{"UnityEngine.Texture2D","UnityEngine.Rect","UnityEngine.Vector2","System.Single"},{texture,&rect,&pivot,&ppu});if(!s)return nullptr;int flags=32;r.call(s,"set_hideFlags",{"UnityEngine.HideFlags"},{&flags});uint32_t sh=r.gchandle_new(s,false);skinSprites[key.UTF8String]=sh;roots.push_back(sh);return s;}
void clearLegacy(){legacyActive=false;legacyStep=-1;legacyJudge=-1;legacyFace.clear();}
void releaseRoots(Runtime&r){for(auto h:roots){P p=target(r,h);try{if(r.alive(p))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{p});}catch(...){}r.gchandle_free(h);}roots.clear();skinTextures.clear();skinSprites.clear();skinAtlasYScale.clear();skinSourceWidths.clear();skinNormalWorldWidths.clear();holdBases.clear();holdOriginalParts.clear();skinBoundTypes.clear();skinBoundNotes.clear();skinHighlights.clear();skinOriginals.clear();for(auto&item:skinOriginalRoots)r.gchandle_free(item.second);skinOriginalRoots.clear();skinFolder.clear();skinFiles.clear();skinAppliedTypes.clear();skinErrors.clear();skinReady=false;}
void loadSkin(Runtime&r){releaseRoots(r);if(!PMSettingBool("skinEnabled"))return;NSString*docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSString*root=[docs stringByAppendingPathComponent:@"PhiMod/resources"];NSString*active=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"active.txt"] encoding:NSUTF8StringEncoding error:nil];active=[active stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!active.length)throw std::runtime_error("No selected resource pack (active.txt missing)");NSString*folder=[[root stringByAppendingPathComponent:active]stringByStandardizingPath];if(![folder hasPrefix:[root stringByAppendingString:@"/"]]||![NSFileManager.defaultManager fileExistsAtPath:folder])throw std::runtime_error("Selected resource pack directory is missing");NSString*required[]={findFile(folder,@"click.png"),findFile(folder,@"drag.png"),findFile(folder,@"flick.png"),findFile(folder,@"hold.png")};for(NSString*p:required)if(!p)throw std::runtime_error("Active skin lacks a required note texture");skinFolder=folder.UTF8String;auto meta=yaml(findFile(folder,@"info.yml") ?: findFile(folder,@"info.yaml"));auto num=[&](const char*k,int d){auto it=meta.find(k);if(it==meta.end())return d;try{return std::clamp(std::stoi(it->second),0,4096);}catch(...){return d;}};auto compact=meta.find("holdCompact");skinHoldCompact=compact!=meta.end()&&std::regex_search(compact->second,std::regex("^\\s*(true|True|TRUE|1)(\\s|#|$)"));auto hold=pairValue(meta,"holdAtlas",50,50),holdMH=pairValue(meta,"holdAtlasMH",hold.first,hold.second),fxAtlas=pairValue(meta,"hitFx",5,6);skinTail=hold.first;skinHead=hold.second;skinTailMH=holdMH.first;skinHeadMH=holdMH.second;skinCols=std::clamp(fxAtlas.first,1,32);skinRows=std::clamp(fxAtlas.second,1,32);for(int i=0;i<4;++i){NSString*p=required[i];skinFiles[std::vector<std::string>{"click.png","drag.png","flick.png","hold.png"}[i]]=p;loadTexture(r,p);}for(NSString*base in @[@"click.png",@"drag.png",@"flick.png",@"hold.png"]){NSString*mh=[base.stringByDeletingPathExtension stringByAppendingString:@"_mh.png"];NSString*p=findFile(folder,mh);if(p){skinFiles[mh.UTF8String]=p;loadTexture(r,p);}}NSString*fxFile=findFile(folder,@"hit_fx.png");if(fxFile)loadTexture(r,fxFile);skinReady=true;logf("Skin runtime prepared files=%lu",(unsigned long)skinTextures.size());}
NSString*skinPath(const char*name){return [NSString stringWithUTF8String:(skinFolder+"/"+name).c_str()];}
bool isHighlight(Runtime&r,P sprite){if(!r.alive(sprite))return false;NSString*n=r.string(r.call(sprite,"get_name"));NSString*l=n.lowercaseString;return [l containsString:@"hl"]||[l containsString:@"highlight"]||[l containsString:@"_mh"];}
void applyNote(Runtime&r,P c,bool isHold){if(!skinReady||!c)return;P note=r.get<P>(c,"noteInfor");if(!note)return;int type=r.get<int>(note,"type");if(!isHold){P old=r.get<P>(c,"noteImage");const char*base=type==1?"click":type==2?"drag":"flick";NSString*file=skinFiles[std::string(base)+".png"];if(skinHighlights.count(c)?skinHighlights[c]:isHighlight(r,old)){NSString*mh=skinFiles[std::string(base)+"_mh.png"];if(mh)file=mh;}P s=skinSprite(r,file,-1,skinOriginals.count(c)?skinOriginals[c]:old),renderer=r.get<P>(c,"_spriteRenderer");if(s&&r.alive(renderer)){r.call(renderer,"set_sprite",{"UnityEngine.Sprite"},{s});r.put(c,"noteImage",s);if(r.call(renderer,"get_sprite")!=s)throw std::runtime_error("Note skin sprite readback mismatch");if(skinAppliedTypes.insert(type).second)logf("Skin applied and verified type=%d",type);}return;}
 P body=r.get<P>(c,"_holdSpriteRenderer"),head=r.get<P>(c,"_holdHeadSpriteRenderer"),tail=r.get<P>(c,"_holdEndSpriteRenderer1");if(!r.alive(body))return;P old=r.call(body,"get_sprite");Bounds ob=r.unbox<Bounds>(r.call(skinOriginals.count(c)?skinOriginals[c]:old,"get_bounds"));V3 originalScale=r.unbox<V3>(r.call(r.call(c,"get_transform"),"get_localScale"));holdBases.emplace(c,std::make_pair(ob.extents.y*2.f,ob.center.y-ob.extents.y));NSString*path=skinFiles["hold.png"];if(skinHighlights.count(c)?skinHighlights[c]:isHighlight(r,old)){NSString*mh=skinFiles["hold_mh.png"];if(mh)path=mh;}P original=skinOriginals.count(c)?skinOriginals[c]:old;auto parts=holdOriginalParts.find(c);P hs=skinSprite(r,path,0,parts!=holdOriginalParts.end()?parts->second[0]:original),bs=skinSprite(r,path,1,original),ts=skinSprite(r,path,2,parts!=holdOriginalParts.end()?parts->second[2]:original);if(r.alive(head)&&hs)r.call(head,"set_sprite",{"UnityEngine.Sprite"},{hs});if(bs)r.call(body,"set_sprite",{"UnityEngine.Sprite"},{bs});if(r.alive(tail)&&ts)r.call(tail,"set_sprite",{"UnityEngine.Sprite"},{ts});int drawMode=0;for(P renderer:{head,body,tail})if(r.alive(renderer))r.call(renderer,"set_drawMode",{"UnityEngine.SpriteDrawMode"},{&drawMode});if(bs&&skinAppliedTypes.insert(3).second)logf("Skin applied and verified type=3 (native widths, per-part pivots, source-aware geometry)");(void)originalScale;}
void adjustHold(Runtime&r,P c){
 auto it=holdBases.find(c);if(it==holdBases.end())return;
 P body=r.get<P>(c,"_holdSpriteRenderer"),tr=r.call(c,"get_transform");if(!r.alive(body))return;
 P current=r.call(body,"get_sprite");if(!r.alive(current))return;
 Bounds b=r.unbox<Bounds>(r.call(current,"get_bounds"));float height=b.extents.y*2;if(height<=.0001f)return;
 V3 scale=r.unbox<V3>(r.call(tr,"get_localScale")),pos=r.unbox<V3>(r.call(tr,"get_localPosition"));
 // RPE endpoints already used the replacement sprite bounds in noteMoved.
 // Only native constant-speed geometry needs old-height/new-height conversion.
 if(!pmcontent::sourceHoldGeometry(r,c)){
  float prev=scale.y;scale.y*=it->second.first/height;
  pos.y+=it->second.second*prev-(b.center.y-b.extents.y)*scale.y;
  r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});r.call(tr,"set_localPosition",{"UnityEngine.Vector3"},{&pos});
 }
 for(int i=0;i<2;++i){P go=r.get<P>(c,i?"holdEnd":"holdHead");if(!r.alive(go))continue;
  P child=r.call(go,"get_transform");V3 cs=r.unbox<V3>(r.call(child,"get_localScale"));
  cs.y=std::fabs(scale.x/std::max(.00001f,std::fabs(scale.y)));r.call(child,"set_localScale",{"UnityEngine.Vector3"},{&cs});
  if(i||!r.get<bool>(c,"_holdHeadIsDestroyed")){V3 cp=r.unbox<V3>(r.call(child,"get_localPosition"));cp.y=b.center.y+(i?b.extents.y:-b.extents.y);
   P cap=r.get<P>(c,i?"_holdEndSpriteRenderer1":"_holdHeadSpriteRenderer");P sprite=r.alive(cap)?r.call(cap,"get_sprite"):nullptr;
   if(r.alive(sprite)){Bounds cb=r.unbox<Bounds>(r.call(sprite,"get_bounds"));cp.y=rpeHoldCapPosition(cp.y,cb.center.y,cb.extents.y,cs.y,i!=0,skinHoldCompact);}
   r.call(child,"set_localPosition",{"UnityEngine.Vector3"},{&cp});}
 }
}
NSString*resourceFolder(NSString*identifier){
 // Official IDs have no local asset directory. Keep absence as nil rather
 // than constructing std::string from a null UTF8String pointer.
 if(!identifier.length)return nil;
 NSString*folder=[PMContentStore.shared asset:identifier];
 if(!folder.length)return nil;
 NSDictionary*song=nil;
 for(NSDictionary*entry in [PMContentStore.shared snapshot][@"songs"])if([entry[@"id"] isEqualToString:identifier]){song=entry;break;}
 if(!song)return nil;
 NSString*sub=[song[@"resourceRoot"] isKindOfClass:NSString.class]?song[@"resourceRoot"]:@"";
 NSString*root=[folder stringByStandardizingPath];
 if(sub.length){folder=[[root stringByAppendingPathComponent:sub]stringByStandardizingPath];if(![folder isEqualToString:root]&&![folder hasPrefix:[root stringByAppendingString:@"/"]])return nil;}
 BOOL directory=NO;
 return [NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&directory]&&directory?folder:nil;
}
std::string hexDecodePath(NSString*value){NSData*d=[[value stringByReplacingOccurrencesOfString:@" " withString:@""] dataUsingEncoding:NSASCIIStringEncoding];if(!d.length||d.length%2)return {};const unsigned char*p=static_cast<const unsigned char*>(d.bytes);std::string out;out.reserve(d.length/2);for(NSUInteger i=0;i<d.length;i+=2){unsigned hi=p[i]>='0'&&p[i]<='9'?p[i]-'0':p[i]>='a'&&p[i]<='f'?p[i]-'a'+10:p[i]>='A'&&p[i]<='F'?p[i]-'A'+10:99;unsigned lo=p[i+1]>='0'&&p[i+1]<='9'?p[i+1]-'0':p[i+1]>='a'&&p[i+1]<='f'?p[i+1]-'a'+10:p[i+1]>='A'&&p[i+1]<='F'?p[i+1]-'A'+10:99;if(hi>15||lo>15)return {};out.push_back((char)((hi<<4)|lo));}return out;}
void destroyVideoObject(Runtime&r,uint32_t &handle,bool releaseTexture){
 if(!handle)return;
 P object=target(r,handle);
 try{
  if(r.alive(object)){
   try{if(releaseTexture)r.call(object,"Release");}catch(...){}
   try{r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{object});}catch(...){}
  }
 }catch(...){}
 r.gchandle_free(handle);handle=0;
}
void clearVideos(Runtime&r){
 for(Video &v:videos){
  try{if(r.alive(v.player))r.call(v.player,"Stop");}catch(...){}
  destroyVideoObject(r,v.go,false);
  destroyVideoObject(r,v.texture,true);
  v.player=v.raw=nullptr;
 }
 videos.clear();
}
void prepareVideosFromEffects(Runtime&r,P level,NSString*folder){
 NSString*extensions=[folder stringByAppendingPathComponent:@"extensions"];
 NSString*effects=[folder stringByAppendingPathComponent:@"effects.tsv"];
 NSString*extra=[extensions stringByAppendingPathComponent:@"extra.json"];
 if(![NSFileManager.defaultManager fileExistsAtPath:effects]&&[NSFileManager.defaultManager fileExistsAtPath:extra]){
  NSError*error=nil;
  if(!PMConvertExtraJSON(extra,effects,&error)){logf("RPE effects conversion failed: %s",error.localizedDescription.UTF8String);return;}
 }
 NSString*text=[NSString stringWithContentsOfFile:effects encoding:NSUTF8StringEncoding error:nil];
 if(!text.length)return;
 std::vector<Video> parsed(33);
 std::vector<bool> used(33,false);
 for(NSString*line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
  std::istringstream in(line.UTF8String?line.UTF8String:"");
  char tag;
  if(!(in>>tag))continue;
  if(tag=='V'){
   int index;double start;std::string scale,path;
   if(!(in>>index>>start>>scale>>path)||index<0||index>=33||!std::isfinite(start))continue;
   NSString *encoded=[NSString stringWithUTF8String:path.c_str()];
   std::string decoded=encoded?hexDecodePath(encoded):std::string();
   if(decoded.empty())continue;
   NSString *relative=[NSString stringWithUTF8String:decoded.c_str()];
   if(!relative.length||relative.isAbsolutePath||[relative containsString:@"\\"])continue;
   BOOL safe=YES;for(NSString*part in [relative componentsSeparatedByString:@"/"])if(!part.length||[part isEqualToString:@"."]||[part isEqualToString:@".."])safe=NO;
   if(!safe)continue;
   NSString *video=[[extensions stringByAppendingPathComponent:relative]stringByStandardizingPath];
   if(![video hasPrefix:[extensions stringByAppendingString:@"/"]]||![NSFileManager.defaultManager fileExistsAtPath:video])continue;
   parsed[index].index=index;parsed[index].start=start;parsed[index].scale=scale;parsed[index].path=video.UTF8String;used[index]=true;
  }else if(tag=='K'){
   char kind;int index,channel;std::string name;TrackEvent event;
   if((in>>kind>>index>>name>>channel>>event.s>>event.e>>event.a>>event.b)&&kind=='V'&&index>=0&&index<33&&channel>=0&&channel<4&&std::isfinite(event.s)&&std::isfinite(event.e)&&std::isfinite(event.a)&&std::isfinite(event.b)){
    NSString *encoded=[NSString stringWithUTF8String:name.c_str()];std::string decoded=encoded?hexDecodePath(encoded):std::string();
    if(!decoded.empty())parsed[index].tracks[decoded].push_back(event);
   }
  }
 }
 for(int i=0;i<33;i++)if(used[i]&&!parsed[i].path.empty()){
  for(auto&entry:parsed[i].tracks)std::stable_sort(entry.second.begin(),entry.second.end(),[](const auto&a,const auto&b){return a.s<b.s;});
  videos.push_back(std::move(parsed[i]));
 }
 if(!videos.empty()&&level&&!videoLevel)videoLevel=r.gchandle_new(level,false);
 logf("RPE videos loaded from effects.tsv: %lu",(unsigned long)videos.size());
}
void prepareVideos(Runtime&r,P level){
 clearVideos(r);
 P current=videoLevel?target(r,videoLevel):nullptr;
 if(videoLevel&&current!=level){r.gchandle_free(videoLevel);videoLevel=0;}
 if(!videoLevel&&level)videoLevel=r.gchandle_new(level,false);
 P info=r.get<P>(r.mainGame(),"levelStartInfo");
 NSString*identifier=info?r.string(r.get<P>(info,"songsId")):nil;
 if(!identifier.length)return;
 NSString*folder=resourceFolder(identifier);
 if(!folder.length)return;
 prepareVideosFromEffects(r,level,folder);
}
double trackAt(const std::vector<TrackEvent>&a,double now,double fallback){
 if(a.empty())return fallback;
 const TrackEvent*last=nullptr;
 for(auto&e:a){if(e.s<=now)last=&e;else break;}
 if(!last)return fallback;
 if(last->e<=last->s||now>=last->e)return last->b;
 double q=std::clamp((now-last->s)/(last->e-last->s),0.,1.);
 return last->a+(last->b-last->a)*q;
}
P addComponent(Runtime&r,P go,P type){return r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(type))});}
void makeVideo(Runtime&r,Video&v){
 if(v.go||v.failed)return;
 try{
  P go=r.object_new(r.type("UnityEngine","GameObject"));
  if(!go)throw std::runtime_error("RPE video GameObject allocation failed");
  r.call(go,".ctor",{"System.String"},{r.string_new("PhiMod_RPE_Video")});
  v.go=r.gchandle_new(go,false);
  P camera=r.stat(r.type("UnityEngine","Camera"),"get_main");
  if(!camera)throw std::runtime_error("RPE video main camera missing");
  P level=target(r,videoLevel),info=level?r.get<P>(level,"levelInformation"):nullptr;
  P lineList=info?r.get<P>(info,"judgeLines"):nullptr;
  P first=r.count(lineList)?r.at(lineList,0):nullptr;
  bool no=false,yes=true;
  if(first){int layer=r.unbox<int>(r.call(first,"get_layer"));r.call(go,"set_layer",{"System.Int32"},{&layer});}
  P canvas=addComponent(r,go,r.type("UnityEngine","Canvas"));
  int mode=2,order=1;
  r.call(canvas,"set_renderMode",{"UnityEngine.RenderMode"},{&mode});
  r.call(canvas,"set_worldCamera",{"UnityEngine.Camera"},{camera});
  r.call(canvas,"set_overrideSorting",{"System.Boolean"},{&yes});
  r.call(canvas,"set_sortingOrder",{"System.Int32"},{&order});
  if(first){
   P renderer=r.call(first,"GetComponentInChildren",{"System.Type"},{r.type_get_object(r.class_get_type(r.type("UnityEngine","SpriteRenderer")))});
   if(renderer){int sorting=r.unbox<int>(r.call(renderer,"get_sortingLayerID"));r.call(canvas,"set_sortingLayerID",{"System.Int32"},{&sorting});}
  }
  P tr=r.call(go,"get_transform");
  float ortho=r.unbox<float>(r.call(camera,"get_orthographicSize"));
  float cameraAspect=r.unbox<float>(r.call(camera,"get_aspect"));
  float aspect=std::min(cameraAspect,16.f/9.f);
  if(!std::isfinite(aspect)||aspect<=0)throw std::runtime_error("Invalid RPE video camera aspect");
  float width=2*ortho*aspect;
  V2 size{width,width/aspect};
  V3 position{0,0,-5};
  r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});
  r.call(tr,"set_localPosition",{"UnityEngine.Vector3"},{&position});
  P raw=addComponent(r,go,r.type("UnityEngine.UI","RawImage"));v.raw=raw;
  r.call(raw,"set_raycastTarget",{"System.Boolean"},{&no});
  P texture=r.object_new(r.type("UnityEngine","RenderTexture"));
  if(!texture)throw std::runtime_error("RPE video RenderTexture allocation failed");
  v.texture=r.gchandle_new(texture,false);
  int texWidth=960,texHeight=std::max(1,(int)(960/aspect)),depth=0;
  r.call(texture,".ctor",{"System.Int32","System.Int32","System.Int32"},{&texWidth,&texHeight,&depth});
  r.call(texture,"Create");
  r.call(raw,"set_texture",{"UnityEngine.Texture"},{texture});
  P player=addComponent(r,go,r.type("UnityEngine.Video","VideoPlayer"));v.player=player;
  bool loop=false,wait=true,skip=true;
  r.call(player,"set_playOnAwake",{"System.Boolean"},{&loop});
  r.call(player,"set_isLooping",{"System.Boolean"},{&loop});
  r.call(player,"set_waitForFirstFrame",{"System.Boolean"},{&wait});
  r.call(player,"set_skipOnDrop",{"System.Boolean"},{&skip});
  int render=2,aspectMode=v.scale=="fit"?3:v.scale=="stretch"?5:4,audio=0,timeReference=2;
  r.call(player,"set_renderMode",{"UnityEngine.Video.VideoRenderMode"},{&render});
  r.call(player,"set_targetTexture",{"UnityEngine.RenderTexture"},{texture});
  r.call(player,"set_aspectRatio",{"UnityEngine.Video.VideoAspectRatio"},{&aspectMode});
  r.call(player,"set_audioOutputMode",{"UnityEngine.Video.VideoAudioOutputMode"},{&audio});
  r.call(player,"set_timeReference",{"UnityEngine.Video.VideoTimeReference"},{&timeReference});
  NSURL*u=[NSURL fileURLWithPath:[NSString stringWithUTF8String:v.path.c_str()]];
  r.call(player,"set_url",{"System.String"},{r.managedString(u.absoluteString)});
  r.call(player,"Prepare");
 }catch(const std::exception&e){v.failed=true;logf("RPE video setup failed: %s",e.what());}
}
void updateVideos(Runtime&r,P progress){
 if(videos.empty()||!videoLevel)return;
 P level=target(r,videoLevel),info=level?r.get<P>(level,"levelInformation"):nullptr;
 if(!info||!r.get<bool>(info,"chartLoaded"))return;
 double now=r.get<float>(progress,"nowTime");bool playing=r.get<bool>(progress,"isPlaying");
 for(auto&v:videos){
  if(v.failed||v.path.empty())continue;
  try{
   makeVideo(r,v);
   if(!v.player||!r.unbox<bool>(r.call(v.player,"get_isPrepared")))continue;
   double length=r.unbox<double>(r.call(v.player,"get_length")),time=now-v.start;
   bool active=time>=0&&time<length;
   double alpha=active?trackAt(v.tracks["alpha"],now,1):0,dim=trackAt(v.tracks["dim"],now,0);
   Color color{(float)(1-dim),(float)(1-dim),(float)(1-dim),(float)alpha};
   r.call(v.raw,"set_color",{"UnityEngine.Color"},{&color});
   bool running=r.unbox<bool>(r.call(v.player,"get_isPlaying"));
   if(active){
    r.call(v.player,"set_externalReferenceTime",{"System.Double"},{&time});
    if(playing&&!running){if(!v.begun){r.call(v.player,"set_time",{"System.Double"},{&time});v.begun=true;}r.call(v.player,"Play");}
    else if(!playing&&running)r.call(v.player,"Pause");
   }else if(running)r.call(v.player,"Pause");
  }catch(const std::exception&e){v.failed=true;logf("RPE video update failed: %s",e.what());}
 }
}

void prepareLegacy(Runtime&r){clearLegacy();if(!PMSettingBool("legacyEffects"))return;try{P info=r.get<P>(r.mainGame(),"levelStartInfo");NSString*id=info?r.string(r.get<P>(info,"songsId")):nil;NSString*folder=id?[PMContentStore.shared asset:id]:nil;NSString*marker=folder?[folder stringByAppendingPathComponent:@"legacy-effect.txt"]:nil;NSString*value=marker?[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil]:nil;if([value isEqualToString:@"yukifuri-2023-v1\n"]){legacyActive=true;PMDiagnosticsWrite("Legacy Yukifuri runtime enabled");}}catch(const std::exception&e){logf("Legacy effect prepare failed: %s",e.what());}}
void updateLegacy(Runtime&r,P progress){
 if(!legacyActive||!progress)return;
 float now=r.get<float>(progress,"nowTime");
 int step=phimod::legacy::faceStep(now);
 if(step>legacyStep){legacyStep=step;if(step>31)legacyFace.clear();else if(step>=0){if(step%8==0){legacyFace="(o_o)";legacyJudge=-1;}else if(step%8==1)legacyFace="(o_w)";}}
 if(legacyStep>=0&&legacyStep<=31&&legacyJudge>=0){legacyFace=legacyJudge==0?"(x_x)":legacyJudge==1?"(^_^)":"(*_*)";legacyJudge=-1;}
 P level=videoLevel?target(r,videoLevel):nullptr;
 if(level){try{P text=r.get<P>(level,"songsLevel");if(r.alive(text))r.text(text,now>phimod::legacy::nightmare?"SP  Lv.?":"lN  Lv.I2");}catch(...) {}}
 P score=r.get<P>(progress,"scoreControl");if(!score)return;
 if(!legacyFace.empty()){try{r.text(r.get<P>(score,"combo"),legacyFace.c_str());r.text(r.get<P>(score,"blockedCombo"),legacyFace.c_str());}catch(...) {}}
 if(now<phimod::legacy::nightmare+.8f&&!PMSettingBool("noCombo")){
  try{P info=r.get<P>(progress,"levelInformation");int total=r.get<int>(info,"numOfNotes");int perfect=r.get<int>(score,"perfect"),good=r.get<int>(score,"good"),combo=r.get<int>(score,"maxcombo");int display=(int)std::lround((900000.f*(perfect+.65f*good)+100000.f*combo)/std::max(1,total));char digits[16];snprintf(digits,sizeof(digits),"%07d",std::min(1000000,display));r.text(r.get<P>(score,"score"),digits);r.text(r.get<P>(score,"blockedScore"),digits);}catch(...) {}}
}
} // anonymous namespace
void beforeNoteMove(Runtime&r,void*control,bool hold){
 if(!skinReady||!control)return;
 try{
  P c=control,note=r.get<P>(c,"noteInfor");if(!note)return;
  auto bound=skinBoundNotes.find(c);if(bound!=skinBoundNotes.end()&&bound->second==note)return;
  int type=r.get<int>(note,"type");const char*base=hold?"hold":type==2?"drag":type==4?"flick":"click";
  P original=nullptr,images=nullptr;
  if(hold){images=r.get<P>(c,"noteImages");if(!images||r.array_length(images)<3)throw std::runtime_error("Hold skin source array missing");original=r.arrayAt(images,1);}
  else original=r.get<P>(c,"noteImage");
  if(!r.alive(original))return;
  bool highlight=isHighlight(r,original);skinHighlights[c]=highlight;
  skinOriginals[c]=original;if(!skinOriginalRoots.count(original))skinOriginalRoots[original]=r.gchandle_new(original,false);
  // Keep original sprite alive while replacement caching uses its identity.
  // Do not add to roots: originals belong to the game, not our Destroy list.
  // Read the untouched normal prefab, not the highlighted instance sprite.
  if(!skinNormalWorldWidths.count(std::string(base)+".png/"+(hold?"2":"-1"))){
  P line=r.get<P>(c,"judgeLine");P prefab=r.get<P>(line,hold?"Hold":type==2?"Drag":type==4?"Flick":"Click");
  P templateControl=r.component(prefab,r.klass(hold?"HoldControl":type==2?"DragControl":type==4?"FlickControl":"ClickControl"));
  P normalImages=hold?r.get<P>(templateControl,"noteImages"):nullptr;
  for(int part=hold?0:-1;part<(hold?3:0);++part){
   std::string widthKey=std::string(base)+".png/"+std::to_string(part);
   if(skinNormalWorldWidths.count(widthKey))continue;
   P sprite=hold?r.arrayAt(normalImages,part):r.get<P>(templateControl,"noteImage");
   Rect rect=r.unbox<Rect>(r.call(sprite,"get_rect"));float ppu=r.unbox<float>(r.call(sprite,"get_pixelsPerUnit"));
   if(ppu>0&&rect.w>0)skinNormalWorldWidths[widthKey]=rect.w/ppu;
  }
  }
  NSString*path=skinFiles[std::string(base)+".png"];
  NSString*mh=skinFiles[std::string(base)+"_mh.png"];if(highlight&&mh)path=mh;
  if(hold){
   std::array<P,3>parts{};
   for(int i=0;i<3;++i){parts[i]=r.arrayAt(images,i);if(!r.alive(parts[i]))throw std::runtime_error("Hold original part missing");if(!skinOriginalRoots.count(parts[i]))skinOriginalRoots[parts[i]]=r.gchandle_new(parts[i],false);}
   holdOriginalParts[c]=parts;
   P replacement=r.array_new(r.type("UnityEngine","Sprite"),3);if(!replacement)throw std::runtime_error("Hold skin array allocation failed");
   uint32_t handle=r.gchandle_new(replacement,false);
   try{
    for(int i=0;i<3;++i){P sprite=skinSprite(r,path,i,parts[i]);if(!sprite)throw std::runtime_error("Hold atlas has an empty region");r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),replacement,{sprite,&i});}
    r.put(c,"noteImages",replacement);
   }catch(...){r.gchandle_free(handle);throw;}r.gchandle_free(handle);
  }else{P sprite=skinSprite(r,path,-1,original);if(!sprite)throw std::runtime_error("Note skin sprite unavailable");r.put(c,"noteImage",sprite);}
  skinBoundNotes[c]=note;
  if(skinBoundTypes.insert(type).second)logf("Skin serialized binding type=%d highlight=%d",type,highlight);
 }catch(const std::exception&e){if(skinErrors.insert(e.what()).second)logf("Skin bind failed: %s",e.what());}
}
void* noteSprite(Runtime&r,int type,int part,void*original){
 if(!skinReady)return original;
 const char*base=type==2?"drag":type==4?"flick":type==3?"hold":"click";
 NSString*path=skinFiles[std::string(base)+".png"];
 if(isHighlight(r,original)){NSString*mh=skinFiles[std::string(base)+"_mh.png"];if(mh)path=mh;}
 P sprite=skinSprite(r,path,type==3?part:-1,original);
 return sprite?sprite:original;
}
void levelBegin(Runtime&r,void*level){PMMetalShadersClear();clearVideos(r);if(videoLevel){r.gchandle_free(videoLevel);videoLevel=0;}releaseRoots(r);if(PMSettingBool("skinEnabled"))logf("Skin load deferred until chart information is ready");if(level)videoLevel=r.gchandle_new(level,false);prepareLegacy(r);}
void levelEnd(Runtime&r){PMMetalShadersClear();clearVideos(r);if(videoLevel){r.gchandle_free(videoLevel);videoLevel=0;}clearLegacy();releaseRoots(r);}
void afterChart(Runtime&r,void*level){try{loadSkin(r);}catch(const std::exception&e){logf("Skin runtime setup failed: %s",e.what());releaseRoots(r);}try{prepareVideos(r,level);}catch(const std::exception&e){logf("RPE video load failed: %s",e.what());}try{P info=r.get<P>(r.mainGame(),"levelStartInfo");NSString*identifier=info?r.string(r.get<P>(info,"songsId")):nil;NSString*folder=resourceFolder(identifier);PMMetalShadersLoad(folder);}catch(const std::exception&e){logf("RPE shader metadata scan failed: %s",e.what());}}
void observe(int rating){if(legacyActive)legacyJudge=rating==0?2:rating==1?1:0;}
void noteMoved(Runtime&r,void*control,bool hold){try{P c=control;
 // Native completion can destroy a controller later in the frame. Do not
 // replace its last sprite or rescale a completed/fading Hold after NoteMove.
 if(!r.alive(c))return;
 if(hold){if(r.get<bool>(c,"judgeOver")||r.get<bool>(c,"missed"))return;}
 else if(r.get<bool>(c,"isJudged"))return;
 applyNote(r,c,hold);if(hold)adjustHold(r,c);}catch(const std::exception&e){if(skinErrors.insert(e.what()).second)logf("Skin note update failed: %s",e.what());}}
void tick(Runtime&r,void*progress){PMMetalShadersTick(r.get<float>(progress,"nowTime"));try{updateVideos(r,progress);updateLegacy(r,progress);}catch(const std::exception&e){logf("Feature update failed: %s",e.what());}}
}



