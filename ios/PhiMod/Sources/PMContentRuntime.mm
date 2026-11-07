#include "PMContentRuntime.hpp"
#include "PMUnlockRuntime.hpp"
#include "PMRuntimeFeatures.hpp"
#import "PMContentStore.h"
#import "PMChartConvert.h"
#import "PMDiagnostics.h"
#import "PMSettings.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include "../Core/PMRPECore.hpp"
#include "../Core/PMRPEGeometry.hpp"
#include "../Core/PMHoldTail.hpp"
#include "../Core/PMChartCore.hpp"
#include "../Core/PMRPEHud.hpp"
#include <algorithm>
#include <map>
#include <set>
#include <tuple>
#include <limits>
#include <chrono>
namespace pmcontent {
using pmbridge::P;using pmbridge::Runtime;
namespace {
struct V2{float x,y;};struct V3{float x,y,z;};struct Rect{float x,y,w,h;};struct Color{float r,g,b,a;};struct Bounds{V3 center,extents;};
Runtime*runtime=nullptr;bool playing=false,lastCustom=false,appliedMainline=false;NSUInteger applied=0;NSString*levelID=nil,*pendingSong=nil;int pendingSlot=0;
int hiddenChapterCards=0;uint32_t chapterSelectorRoot=0;
NSDictionary*officialCache=nil;
NSDictionary*baseline=nil;NSArray*originalChapters=nil;NSDictionary*currentChart=nil;NSString*resourceSubdir=@"";
std::map<P,uint32_t>textures;std::map<std::string,uint32_t>assets;std::map<P,std::string>refs;std::map<std::string,int>users;
struct DeferredSelectorAsset {uint32_t root;std::string identifier;bool music;};
std::map<P,DeferredSelectorAsset>selectorAssets;
uint32_t loadingSelector=0;bool completingSelectorAsset=false;
std::set<std::string>selectorSongIDs,selectedAssetIDs;
NSUInteger selectorLibraryRevision=0;int loadingSong=-1,loadingSlot=-1;
float loadingPosition=0;double selectionChangedAt=0;bool selectorDragging=true;
std::set<P>recoveredSourceNotes;
P extrasBoundChart=nullptr;
std::map<std::string,std::map<int,NSDictionary*>>variants;std::map<P,NSDictionary*>extras;std::map<P,V3>noteScales,lineScales;std::map<int,uint32_t>decorText,decorImage;
struct StoryVisual {P go=nullptr,tr=nullptr,graphic=nullptr,canvas=nullptr;bool text=false,visible=true;NSString*lastText=nil;};
std::map<int,StoryVisual>storyVisuals;
std::map<int,P>plainLineRenderers;std::map<int,double>storyRetry;std::set<int>storyReported;
NSArray*storyFiles=nil;bool storyIndexed=false;P storyFrameCamera=nullptr;float storyFrameWidth=0;std::map<std::string,P>storySprites;P storyMaterial=nullptr;
struct Fake{NSDictionary*note;int line;bool below;double start,end;};
struct FakeVisualCache{P transform=nullptr;P capTransforms[2]{};Bounds bounds{};bool shown=false;bool capShown[2]{false,false};bool colorSet=false,scaleSet=false;Color color{};V3 scale{};};
std::map<size_t,FakeVisualCache>fakeVisualCache;
std::vector<size_t>fakeSchedule;std::set<size_t>activeFakes;size_t fakeCursor=0;bool fakeScheduleReady=false;double fakeLastTime=0;
struct ControlPoint{double x,value;int easing;};
std::map<NSArray*,std::vector<ControlPoint>>controlCache;
std::vector<Fake>fakeNotes;std::map<int,std::vector<phimod::RpeFloorSegment>>sourceFloors;std::map<size_t,std::pair<uint32_t,uint32_t>>fakeHoldEnds;std::map<size_t,uint32_t>fakeRenderers;std::map<size_t,V3>fakeScales;std::map<size_t,double>fakeRetryAt;std::set<size_t>failedFakes;std::vector<uint32_t>visualRoots;
// Engine-provided baseline sortingOrder per judge line, so pmDecor.zOrder=0
// never sinks a custom-chart line behind the background.
// Effect prefabs are shared. Restore them when leaving the custom chart.
struct HitFXRenderer {uint32_t root;int layer,order;};
struct HitFXPrefab {std::vector<HitFXRenderer> renderers;int appliedLayer=0,appliedFloor=-1;};
std::map<P,HitFXPrefab>holdHitFX;
void restoreHoldHitFX(Runtime&r){
 for(auto&entry:holdHitFX)for(auto&saved:entry.second.renderers){
  P renderer=r.gchandle_get_target(saved.root);
  try{if(r.alive(renderer)){r.call(renderer,"set_sortingLayerID",{"System.Int32"},{&saved.layer});r.call(renderer,"set_sortingOrder",{"System.Int32"},{&saved.order});}}catch(const std::exception&e){PMDiagnosticsWrite([NSString stringWithFormat:@"Hold hit FX restore failed: %s",e.what()].UTF8String);}
  r.gchandle_free(saved.root);
 }
 holdHitFX.clear();
}
void clearHud(Runtime&r);
void clearSkew(Runtime&r);
std::map<int,int>hudLines;uint32_t hudLevel=0;
std::set<int>uiControlLines;
std::set<int>inertLineVisuals;bool rpeIntroRetired=false;std::set<int>reportedLineAlphaCorrections;
std::map<P,int>lineBaseOrder;std::vector<int>storyOrders;int storyHoldOrder=1028,storyNoteOrder=1030;
// Fake notes that already failed to build; never retried in the same chart.
void log(NSString*s){PMDiagnosticsWrite(s.UTF8String);}
P target(Runtime&r,uint32_t h){return h?r.gchandle_get_target(h):nullptr;}
P keep(Runtime&r,P p){if(p)visualRoots.push_back(r.gchandle_new(p,false));return p;}
P decode(Runtime&r,id value,const char*name){NSData*d=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];NSString*s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];if(!s)throw std::runtime_error("Invalid content JSON");return r.stat(r.type("UnityEngine","JsonUtility"),"FromJson",{"System.String","System.Type"},{r.managedString(s),r.type_get_object(r.class_get_type(r.klass(name)))});}
id encode(Runtime&r,P p){P text=r.stat(r.type("UnityEngine","JsonUtility"),"ToJson",{"System.Object"},{p});NSData*d=[r.string(text)dataUsingEncoding:NSUTF8StringEncoding];return d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;}
int slotIndex(NSString*s){NSInteger i=[@[@"EZ",@"HD",@"IN",@"AT"]indexOfObject:s ?: @"IN"];return i==NSNotFound?2:(int)i;}
NSDictionary*songFor(NSString*identifier,int slot){auto it=variants.find(identifier.UTF8String);if(it!=variants.end()){auto found=it->second.find(slot);if(found!=it->second.end())return found->second;}for(NSDictionary*s in [PMContentStore.shared snapshot][@"songs"])if([s[@"id"] isEqualToString:identifier])return s;return nil;}
NSString*groupFor(NSString*identifier){for(NSDictionary*s in [PMContentStore.shared snapshot][@"songs"])if([s[@"id"] isEqualToString:identifier])return [s[@"groupId"] length]?s[@"groupId"]:identifier;return identifier;}
void capture(Runtime&r){if(baseline)return;P gi=r.mainGame();P song=r.get<P>(gi,"song"),chapters=r.get<P>(gi,"chapters");if(!song||!chapters)return;baseline=encode(r,song);NSMutableArray*a=[NSMutableArray new];for(uintptr_t i=0,n=r.array_length(chapters);i<n;++i){id c=encode(r,r.arrayAt(chapters,(int)i));if(c)[a addObject:c];}originalChapters=a;@synchronized(PMContentStore.shared){officialCache=@{@"songBase":baseline,@"chapters":originalChapters};}}
NSDictionary*nativeSong(NSString*group,NSDictionary*s,std::map<int,NSDictionary*>&members){NSMutableArray*difficulty=[NSMutableArray new],*charters=[NSMutableArray new],*mods=[NSMutableArray new],*images=[NSMutableArray new],*unlocks=[NSMutableArray new];for(int i=0;i<4;++i){NSDictionary*v=members.count(i)?members[i]:nil;[difficulty addObject:v?@(MAX(.1,[v[@"difficulty"] doubleValue])):@0];[charters addObject:v[@"charter"] ?: @""];[mods addObject:@{@"levelMods":@[]}];[images addObject:@[]];[unlocks addObject:@{@"unlockType":@(-1),@"unlockInfo":@[]}];}return @{@"songsId":group,@"songsKey":group,@"songsName":s[@"title"] ?: group,@"songsTitle":s[@"title"] ?: group,@"composer":s[@"composer"] ?: @"",@"illustrator":s[@"illustrator"] ?: @"",@"difficulty":difficulty,@"charter":charters,@"levels":@[@"EZ",@"HD",@"IN",@"AT"],@"previewTime":s[@"preview"] ?: @0,@"previewEndTime":s[@"previewEnd"] ?: @15,@"unlockInfo":unlocks,@"judgeLineImages":images,@"levelMods":mods};}
void apply(Runtime&r){capture(r);if(!baseline||playing)return;NSDictionary*db=[PMContentStore.shared snapshot];variants.clear();NSDictionary*selections=db[@"chartSelections"];
 for(NSDictionary*s in db[@"songs"]){NSString*g=[s[@"groupId"] length]?s[@"groupId"]:s[@"id"];int slot=slotIndex(s[@"level"]);auto&group=variants[g.UTF8String];NSString*selected=selections[[NSString stringWithFormat:@"%@@%d",g,slot]];if(!group.count(slot)||[selected isEqualToString:s[@"id"]])group[slot]=s;}
 NSMutableDictionary*songBase=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:baseline options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];NSMutableDictionary*official=[NSMutableDictionary new];for(NSString*k in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSMutableDictionary*s in songBase[k])official[s[@"songsId"]]=s;
 for(auto&g:variants){NSString*id=[[NSString alloc]initWithUTF8String:g.first.c_str()];NSDictionary*s=g.second.begin()->second;NSDictionary*local=nativeSong(id,s,g.second);NSMutableDictionary*existing=official[id];if(existing){NSMutableArray*d=[existing[@"difficulty"] mutableCopy],*c=[existing[@"charter"] mutableCopy];for(auto&v:g.second)if(v.first<(int)d.count){d[v.first]=local[@"difficulty"][v.first];if(v.first<(int)c.count)c[v.first]=local[@"charter"][v.first];}existing[@"difficulty"]=d;existing[@"charter"]=c;}else[songBase[@"mainSongs"] addObject:local];}
 for(NSString*id in db[@"overrides"]){NSMutableDictionary*s=official[id];if(s){NSDictionary*patch=db[@"overrides"][id];for(NSString*k in @[@"songsName",@"songsTitle",@"composer",@"illustrator",@"difficulty",@"charter"])if(patch[k])s[k]=patch[k];}}
 NSMutableArray*chapters=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:originalChapters options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];for(NSDictionary*c in db[@"chapters"]){NSMutableArray*items=[NSMutableArray new];NSMutableSet*seen=[NSMutableSet new];for(NSString*id in c[@"songs"]){NSString*g=groupFor(id);if([seen containsObject:g])continue;[seen addObject:g];[items addObject:@{@"songsId":g,@"unlockType":@(-1),@"secretType":@0,@"unlockInfo":@[],@"secretInfo":@[]}];}[chapters addObject:@{@"chapterCode":c[@"id"],@"songInfo":@{@"title":c[@"name"] ?: @"",@"subTitle":c[@"subtitle"] ?: @"",@"banner":c[@"banner"] ?: @"Custom Chapter - Local Practice",@"songs":items},@"unlockInfo":@{@"unlockMode":@0,@"unlockFlag":@"",@"unlockTip":@"",@"fakeCoverFlag":@"",@"fakeCoverCode":@"",@"fakeCoverBlurCode":@""}}];}
 for(NSDictionary*s in db[@"songs"]){NSString*destination=s[@"targetChapter"],*group=groupFor(s[@"id"]);for(NSMutableDictionary*c in chapters)if([c[@"chapterCode"] isEqualToString:destination]){NSMutableArray*a=c[@"songInfo"][@"songs"];BOOL exists=NO;for(NSDictionary*i in a)if([i[@"songsId"] isEqualToString:group])exists=YES;if(!exists)[a addObject:@{@"songsId":group,@"unlockType":@(-1),@"secretType":@0,@"unlockInfo":@[],@"secretInfo":@[]}];}}
  if(PMSettingBool("mainlineUnlock")){
   NSMutableSet*mainlineCodes=[NSMutableSet new],*mainlineGroups=[NSMutableSet new];
   for(NSDictionary*officialChapter in originalChapters){NSString*code=officialChapter[@"chapterCode"];if(![code hasPrefix:@"MainStory"])continue;[mainlineCodes addObject:code];for(NSDictionary*item in officialChapter[@"songInfo"][@"songs"])if(item[@"songsId"])[mainlineGroups addObject:item[@"songsId"]];}
   for(NSMutableDictionary*c in chapters)if([mainlineCodes containsObject:c[@"chapterCode"]]){NSMutableDictionary*u=c[@"unlockInfo"];if([u isKindOfClass:NSDictionary.class]){u[@"unlockMode"]=@0;u[@"unlockFlag"]=@"";u[@"unlockTip"]=@"";u[@"fakeCoverFlag"]=@"";}for(NSMutableDictionary*item in c[@"songInfo"][@"songs"]){item[@"unlockType"]=@(-1);item[@"unlockInfo"]=[NSMutableArray new];item[@"secretType"]=@0;item[@"secretInfo"]=[NSMutableArray new];}}
   for(NSString*key in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSMutableDictionary*song in songBase[key])if([mainlineGroups containsObject:song[@"songsId"]])for(NSMutableDictionary*u in song[@"unlockInfo"]){u[@"unlockType"]=@(-1);u[@"unlockInfo"]=[NSMutableArray new];}
   log(@"Mainline unlock applied to official MainStory chapters only");
  }
 for(NSMutableDictionary*c in chapters){NSString*id=c[@"chapterCode"];NSDictionary*patch=db[@"chapterOverrides"][id];for(NSString*k in @[@"title",@"subTitle",@"banner"])if(patch[k])c[@"songInfo"][k]=patch[k];}
 for(NSDictionary*c in db[@"chapters"]){NSString*before=c[@"before"];if(!before.length)continue;NSUInteger from=NSNotFound,to=NSNotFound;for(NSUInteger i=0;i<chapters.count;++i){if([chapters[i][@"chapterCode"] isEqualToString:c[@"id"]])from=i;if([chapters[i][@"chapterCode"] isEqualToString:before])to=i;}if(from!=NSNotFound&&to!=NSNotFound&&from!=to){id v=chapters[from];[chapters removeObjectAtIndex:from];if(from<to)--to;[chapters insertObject:v atIndex:to];}}
 P gi=r.mainGame(),newBase=decode(r,songBase,"SongBase");uint32_t baseHandle=r.gchandle_new(newBase,false);P arr=r.array_new(r.klass("Chapter"),chapters.count);uint32_t arrHandle=r.gchandle_new(arr,false);try{for(NSUInteger i=0;i<chapters.count;++i){P c=decode(r,chapters[i],"Chapter");uint32_t h=r.gchandle_new(c,false);P info=r.get<P>(c,"songInfo");r.put(info,"<songsBypassLimited>k__BackingField",r.get<P>(info,"songs"));int index=(int)i;r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),arr,{c,&index});r.gchandle_free(h);}r.call(newBase,"MarkDirty");r.put(gi,"song",newBase);r.put(gi,"chapters",arr);}catch(...){r.gchandle_free(arrHandle);r.gchandle_free(baseHandle);throw;}r.gchandle_free(arrHandle);r.gchandle_free(baseHandle);applied=PMContentStore.shared.revision;appliedMainline=PMSettingBool("mainlineUnlock");log([NSString stringWithFormat:@"Content applied: %lu groups, %lu chapters",(unsigned long)variants.size(),(unsigned long)chapters.count]);}
P image(Runtime&r,NSString*path,bool background=false,bool lineTexture=false,V2 anchor={.5f,.5f}){
 if(![NSFileManager.defaultManager fileExistsAtPath:path]){
  NSString*chapterID=path.stringByDeletingLastPathComponent.lastPathComponent;
  for(NSDictionary*song in [PMContentStore.shared snapshot][@"songs"])if([song[@"targetChapter"]isEqualToString:chapterID]){NSString*fallback=[[PMContentStore.shared asset:song[@"id"]]stringByAppendingPathComponent:@"image.png"];if([NSFileManager.defaultManager fileExistsAtPath:fallback]){path=fallback;break;}}
 }
 // Clear cover and background requests share CPU-side image preparation.
 // Bound retained encoded data; Unity object ownership stays in AssetRef.
 static NSCache<NSString*,NSDictionary*>*preparedImages;
 static dispatch_once_t imageCacheOnce;
 dispatch_once(&imageCacheOnce,^{preparedImages=[NSCache new];preparedImages.totalCostLimit=24*1024*1024;preparedImages.countLimit=16;});
 CGFloat maxSide=PMSettingBool("dynamicLargeTextures")?4096.0:2048.0;
 CGFloat maxEncoded=PMSettingBool("dynamicLargeTextures")?64.0:32.0;
 NSDictionary*attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
 if(!attributes)throw std::runtime_error("Cover image is missing");
 NSString*cacheKey=[NSString stringWithFormat:@"%@|%@|%@|%.0f|%lu",path,attributes[NSFileSize],attributes[NSFileModificationDate],maxSide,(unsigned long)PMContentStore.shared.revision];
 NSDictionary*prepared=[preparedImages objectForKey:cacheKey];NSData*encoded=nil;
 CGFloat sourceW=0,sourceH=0;
 if(prepared){encoded=prepared[@"data"];sourceW=[prepared[@"width"] doubleValue];sourceH=[prepared[@"height"] doubleValue];}
 else{
  NSData*original=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
  UIImage*img=original?[UIImage imageWithData:original]:nil;if(!img)throw std::runtime_error("Cover image could not be decoded");
  sourceW=img.size.width*img.scale;sourceH=img.size.height*img.scale;
  if(!std::isfinite(sourceW)||!std::isfinite(sourceH)||sourceW<=0||sourceH<=0)throw std::runtime_error("Cover image dimensions invalid");
  const unsigned char pngMagic[8]={137,80,78,71,13,10,26,10};
  bool directPNG=original.length>=8&&!memcmp(original.bytes,pngMagic,8)&&img.imageOrientation==UIImageOrientationUp&&sourceW<=maxSide&&sourceH<=maxSide;
  if(directPNG)encoded=original;
  else{
   CGFloat factor=MIN(1.0,maxSide/MAX(sourceW,sourceH));
   CGSize size=CGSizeMake(MAX(1,round(sourceW*factor)),MAX(1,round(sourceH*factor)));
   UIGraphicsImageRendererFormat*rendererFormat=[UIGraphicsImageRendererFormat defaultFormat];rendererFormat.scale=1;
   UIGraphicsImageRenderer*renderer=[[UIGraphicsImageRenderer alloc]initWithSize:size format:rendererFormat];
   img=[renderer imageWithActions:^(UIGraphicsImageRendererContext*c){[img drawInRect:CGRectMake(0,0,size.width,size.height)];}];
   encoded=UIImagePNGRepresentation(img);
  }
  if(!encoded.length||encoded.length>maxEncoded*1024*1024||encoded.length>INT_MAX)throw std::runtime_error("Cover PNG encoding failed or exceeded limit");
  // Avoid retaining a single huge image that exceeds the entire cache budget.
  if(encoded.length<=24*1024*1024)[preparedImages setObject:@{@"data":encoded,@"width":@(sourceW),@"height":@(sourceH)} forKey:cacheKey cost:encoded.length];
 }

 P bytes=r.array_new(r.type("System","Byte"),encoded.length);if(!bytes)throw std::runtime_error("Cover managed byte array allocation failed");uint32_t bytesRoot=r.gchandle_new(bytes,false);
 try{void*ptr=(void*)encoded.bytes;int zero=0,count=(int)encoded.length;r.stat(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",{"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,bytes,&count});
  P texture=r.object_new(r.type("UnityEngine","Texture2D"));if(!texture)throw std::runtime_error("Cover texture allocation failed");uint32_t texRoot=r.gchandle_new(texture,false);
  try{int width=2,height=2,format=4;bool mipmaps=false;r.call(texture,".ctor",{"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"},{&width,&height,&format,&mipmaps});bool markNonReadable=true;bool loaded=r.unbox<bool>(r.stat(r.type("UnityEngine","ImageConversion"),"LoadImage",{"UnityEngine.Texture2D","System.Byte[]","System.Boolean"},{texture,bytes,&markNonReadable}));if(!loaded)throw std::runtime_error("Unity ImageConversion rejected cover image");int actualW=r.unbox<int>(r.call(texture,"get_width")),actualH=r.unbox<int>(r.call(texture,"get_height"));Rect rect{0,0,(float)actualW,(float)actualH};V2 pivot=lineTexture?anchor:V2{.5,.5};
   // Android image(): backgrounds cover the native 38.4 x 21.6 canvas.
   // min(PPU) enlarges both axes uniformly, retaining aspect without bars.
   // Use decoded dimensions so downsampling never shrinks world-space coverage.
   float ppu=background?std::min(actualW/38.4f,actualH/21.6f):lineTexture?100.f*actualW/sourceW:100.f;
   if(!std::isfinite(ppu)||ppu<=0)throw std::runtime_error("Invalid background sprite density");
   P sprite=r.stat(r.type("UnityEngine","Sprite"),"Create",{"UnityEngine.Texture2D","UnityEngine.Rect","UnityEngine.Vector2","System.Single"},{texture,&rect,&pivot,&ppu});if(!sprite)throw std::runtime_error("Sprite creation returned null");textures[sprite]=texRoot;r.gchandle_free(bytesRoot);return sprite;}catch(...){r.gchandle_free(texRoot);throw;}
 }catch(...){r.gchandle_free(bytesRoot);throw;}
}
P audio(Runtime&r,NSString*path){
 NSError*error=nil;
 AVAudioFile*file=[[AVAudioFile alloc]initForReading:[NSURL fileURLWithPath:path]
     commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
 if(!file)throw std::runtime_error(error.localizedDescription.UTF8String ?: "Cannot decode custom audio");
 if(file.length<=0||file.length>INT_MAX)throw std::runtime_error("Custom audio length invalid");
 int channels=file.processingFormat.channelCount,frequency=(int)file.processingFormat.sampleRate,samples=(int)file.length;
 if(channels<1||channels>8||frequency<=0)throw std::runtime_error("Custom audio format invalid");
 bool no=false;
 P clip=r.stat(r.type("UnityEngine","AudioClip"),"Create",{"System.String","System.Int32","System.Int32","System.Int32","System.Boolean"},
     {r.string_new("PhiMod custom audio"),&samples,&channels,&frequency,&no});
 if(!clip)throw std::runtime_error("Unity could not allocate custom audio clip");
 uint32_t clipRoot=r.gchandle_new(clip,false);
 try{
  AVAudioPCMBuffer*buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:file.processingFormat frameCapacity:16384];
  if(!buffer)throw std::runtime_error("Custom audio buffer allocation failed");
  int at=0;
  while(at<samples){
   AVAudioFrameCount frames=MIN(16384,samples-at);
   if(![file readIntoBuffer:buffer frameCount:frames error:&error])throw std::runtime_error("Reading custom audio failed");
   int count=(int)buffer.frameLength*channels;
   if(!count)break;
   if(!buffer.floatChannelData)throw std::runtime_error("Custom audio float samples unavailable");
   std::vector<float>pcm(count);
   for(AVAudioFrameCount i=0;i<buffer.frameLength;++i)
    for(int c=0;c<channels;++c)pcm[i*channels+c]=buffer.floatChannelData[c][i];
   P data=r.array_new(r.type("System","Single"),count);
   if(!data)throw std::runtime_error("Managed PCM array allocation failed");
   uint32_t chunkRoot=r.gchandle_new(data,false);
   try{
    void*ptr=pcm.data();int zero=0;
    r.stat(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",
        {"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,data,&count});
    bool ok=r.unbox<bool>(r.call(clip,"SetData",{"System.Single[]","System.Int32"},{data,&at}));
    if(!ok)throw std::runtime_error("Unity rejected custom audio chunk");
   }catch(...){r.gchandle_free(chunkRoot);throw;}
   r.gchandle_free(chunkRoot);
   at+=buffer.frameLength;
  }
  if(at<samples)throw std::runtime_error("Custom audio ended before declared length");
  r.gchandle_free(clipRoot);return clip;
 }catch(...){r.gchandle_free(clipRoot);throw;}
}
NSString*keyID(NSString*key,NSString**kind){if([key hasPrefix:@"PM/"]){NSArray*p=[key componentsSeparatedByString:@"/"];if(p.count<3)return nil;*kind=[[p[2] componentsSeparatedByString:@"@"]firstObject];return p[1];}NSRange pm=[key rangeOfString:@"pm_"];if(pm.location==NSNotFound)return nil;NSString*rest=[key substringFromIndex:pm.location];NSString*id=[[rest componentsSeparatedByString:@"/"]firstObject];if(![PMContentStore.shared asset:id])return nil;NSString*lower=[[key stringByReplacingOccurrencesOfString:id withString:@""]lowercaseString];*kind=[lower containsString:@"music"]?@"music":[lower containsString:@"chart"]?@"chart":[lower containsString:@"blur"]?@"blur":@"image";return id;}
void clearVisuals(Runtime&r){clearSkew(r);clearHud(r);restoreHoldHitFX(r);for(auto h:visualRoots){P p=target(r,h);if(r.alive(p))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{p});r.gchandle_free(h);}visualRoots.clear();extras.clear();extrasBoundChart=nullptr;recoveredSourceNotes.clear();noteScales.clear();lineScales.clear();for(auto e:decorText)r.gchandle_free(e.second);for(auto e:decorImage)r.gchandle_free(e.second);for(auto e:fakeRenderers)r.gchandle_free(e.second);decorText.clear();decorImage.clear();storyVisuals.clear();plainLineRenderers.clear();storySprites.clear();storyMaterial=nullptr;storyRetry.clear();storyReported.clear();storyFiles=nil;storyIndexed=false;storyFrameCamera=nullptr;storyFrameWidth=0;fakeNotes.clear();fakeSchedule.clear();activeFakes.clear();fakeVisualCache.clear();controlCache.clear();fakeCursor=0;fakeScheduleReady=false;fakeLastTime=0;fakeRenderers.clear();fakeScales.clear();fakeRetryAt.clear();for(auto&entry:fakeHoldEnds){r.gchandle_free(entry.second.first);r.gchandle_free(entry.second.second);}fakeHoldEnds.clear();sourceFloors.clear();lineBaseOrder.clear();storyOrders.clear();inertLineVisuals.clear();uiControlLines.clear();rpeIntroRetired=false;reportedLineAlphaCorrections.clear();storyHoldOrder=1028;storyNoteOrder=1030;failedFakes.clear();currentChart=nil;}
void applyCachedChapterCover(Runtime&r,P card,const char*codeField,const char*loaderField){
 NSString*code=r.string(r.get<P>(card,codeField));if(!code.length)return;auto found=assets.find(code.UTF8String);if(found==assets.end())return;P sprite=target(r,found->second);if(!r.alive(sprite))return;
 P loader=r.get<P>(card,loaderField);if(!r.alive(loader))return;bool changed=false;
 P imageComponent=r.get<P>(loader,"_image");if(r.alive(imageComponent)&&r.call(imageComponent,"get_sprite")!=sprite){r.call(imageComponent,"set_sprite",{"UnityEngine.Sprite"},{sprite});changed=true;}
 P spriteRenderer=r.get<P>(loader,"_sprite");if(r.alive(spriteRenderer)&&r.call(spriteRenderer,"get_sprite")!=sprite){r.call(spriteRenderer,"set_sprite",{"UnityEngine.Sprite"},{sprite});changed=true;}
 if(changed)log([NSString stringWithFormat:@"Content chapter cover fallback assigned: %@",r.string(r.get<P>(card,"chapterCode"))]);
}
void syncChapterCoverFallbacks(Runtime&r){P selector=chapterSelectorRoot?r.gchandle_get_target(chapterSelectorRoot):nullptr;if(!r.alive(selector))return;P cards=r.get<P>(selector,"_chapterInfos");for(uintptr_t i=0;cards&&i<r.array_length(cards);++i){P card=r.arrayAt(cards,(int)i);if(r.alive(card)){applyCachedChapterCover(r,card,"coverAssetCode","cover");applyCachedChapterCover(r,card,"coverBlurAssetCode","coverBlur");}}}
}
// Match Android prepareChapterCards: clone before hiding the active template,
// then publish the ordered ChapterInfo array before native Start wires buttons.
void chapterPrepare(Runtime&r,P self){selectorLoadingEnd(r,false);
 if(playing)throw std::runtime_error("Chapter prepare during gameplay");
 capture(r);if(!baseline)throw std::runtime_error("Chapter library is not ready");hiddenChapterCards=0;
 if(applied!=PMContentStore.shared.revision||appliedMainline!=PMSettingBool("mainlineUnlock"))apply(r);
 NSDictionary*db=[PMContentStore.shared snapshot];P panel=r.get<P>(self,"chapterPanel");
 P panelObject=r.call(panel,"get_gameObject");bool includeInactive=false;
 P infos=r.call(panelObject,"GetComponentsInChildren",{"System.Type","System.Boolean"},{r.type_get_object(r.class_get_type(r.klass("ChapterInfo"))),&includeInactive});
 if(!infos||!r.array_length(infos))throw std::runtime_error("ChapterInfo template missing");
 uint32_t infosRoot=r.gchandle_new(infos,false);std::vector<uint32_t>roots;std::vector<P>clones,original,cards;
 P previous=r.get<P>(self,"_chapterInfos");uint32_t previousRoot=r.gchandle_new(previous,false);bool committed=false;
 try{
  P templateCard=nullptr;
  for(uintptr_t i=0;i<r.array_length(infos);++i){P card=r.arrayAt(infos,(int)i);original.push_back(card);NSString*id=r.string(r.get<P>(card,"chapterCode"));if([id isEqualToString:@"Single"])templateCard=card;if(![db[@"hiddenChapters"]containsObject:id])cards.push_back(card);else ++hiddenChapterCards;}
  if(!templateCard)templateCard=original.front();
  P go=r.call(templateCard,"get_gameObject"),parent=r.call(r.call(templateCard,"get_transform"),"get_parent");
  for(NSDictionary*c in db[@"chapters"]){NSString*id=c[@"id"];if([db[@"hiddenChapters"]containsObject:id])continue;
   bool world=false;P clone=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},{go,parent,&world});
   if(!clone)throw std::runtime_error("Chapter clone failed");roots.push_back(r.gchandle_new(clone,false));clones.push_back(clone);
   P card=r.component(clone,r.klass("ChapterInfo"));if(!card)throw std::runtime_error("Chapter clone missing ChapterInfo");
   P nativeChapter=r.call(r.mainGame(),"GetChapterWithCode",{"System.String"},{r.managedString(id)});
   if(!nativeChapter)throw std::runtime_error("Custom chapter data missing from GameInformation");
   P info=r.get<P>(nativeChapter,"songInfo");r.put(card,"chapterCode",r.managedString(id));
   r.put(card,"songInfo",info);r.put(card,"unlockInfo",r.get<P>(nativeChapter,"unlockInfo"));
   r.text(r.get<P>(card,"title"),r.string(r.get<P>(info,"title")).UTF8String);
   r.text(r.get<P>(card,"subTitle"),r.string(r.get<P>(info,"subTitle")).UTF8String);
   NSString*imageKey=[NSString stringWithFormat:@"PM/%@/image@%lu",id,(unsigned long)applied];
   NSString*blurKey=[NSString stringWithFormat:@"PM/%@/blur@%lu",id,(unsigned long)applied];
   r.put(card,"coverAssetCode",r.managedString(imageKey));r.put(card,"coverBlurAssetCode",r.managedString(blurKey));
   bool yes=true;r.call(clone,"SetActive",{"System.Boolean"},{&yes});
   P cover=r.get<P>(card,"cover"),blur=r.get<P>(card,"coverBlur");
   if(r.alive(cover)){r.call(cover,"CheckInitialized");r.call(cover,"SetLowResImage",{"System.String"},{r.managedString(blurKey)});r.call(cover,"set_Code",{"System.String"},{r.managedString(imageKey)});}
   if(r.alive(blur))r.call(blur,"set_Code",{"System.String"},{r.managedString(blurKey)});
   cards.push_back(card);
  }
  for(NSDictionary*c in db[@"chapters"]){NSString*before=c[@"before"];if(!before.length)continue;
   auto from=std::find_if(cards.begin(),cards.end(),[&](P card){return [r.string(r.get<P>(card,"chapterCode"))isEqualToString:c[@"id"]];});
   if(from==cards.end()||[c[@"id"]isEqualToString:before])continue;P card=*from;cards.erase(from);
   auto to=std::find_if(cards.begin(),cards.end(),[&](P v){return [r.string(r.get<P>(v,"chapterCode"))isEqualToString:before];});cards.insert(to,card);
  }
  if(cards.empty())throw std::runtime_error("At least one chapter must remain visible");
  P array=r.array_new(r.klass("ChapterInfo"),cards.size());roots.push_back(r.gchandle_new(array,false));
  for(int i=0;i<(int)cards.size();++i)r.invokeOn(r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"}),array,{cards[i],&i});
  for(P card:original){bool visible=std::find(cards.begin(),cards.end(),card)!=cards.end();r.call(r.call(card,"get_gameObject"),"SetActive",{"System.Boolean"},{&visible});}
  for(int i=0;i<(int)cards.size();++i)r.call(r.call(cards[i],"get_transform"),"SetSiblingIndex",{"System.Int32"},{&i});
  r.put(self,"_chapterInfos",array);committed=true;
  log([NSString stringWithFormat:@"Content chapter cards prepared: visible=%lu custom=%lu",(unsigned long)cards.size(),(unsigned long)clones.size()]);
 }catch(...){
  if(!committed){for(P card:original)try{bool yes=true;r.call(r.call(card,"get_gameObject"),"SetActive",{"System.Boolean"},{&yes});}catch(...){}
   for(P obj:clones)try{bool no=false;r.call(obj,"SetActive",{"System.Boolean"},{&no});r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{obj});}catch(...){}
   try{r.put(self,"_chapterInfos",previous);}catch(...){}
  }
  for(auto h:roots)r.gchandle_free(h);r.gchandle_free(previousRoot);r.gchandle_free(infosRoot);throw;
 }
 for(auto h:roots)r.gchandle_free(h);r.gchandle_free(previousRoot);r.gchandle_free(infosRoot);
 if(chapterSelectorRoot)r.gchandle_free(chapterSelectorRoot);chapterSelectorRoot=r.gchandle_new(self,false);
}
void chapterReady(Runtime&r,P self){
 P cards=r.get<P>(self,"_chapterInfos");
 for(uintptr_t i=0;cards&&i<r.array_length(cards);++i){P card=r.arrayAt(cards,(int)i);NSString*id=r.string(r.get<P>(card,"chapterCode"));if(![id hasPrefix:@"pm_"])continue;
  P chapter=r.call(r.mainGame(),"GetChapterWithCode",{"System.String"},{r.managedString(id)});if(!chapter)continue;
  P info=r.get<P>(chapter,"songInfo");NSString*variant=pmunlock::coverPath(r,id).lastPathComponent;NSString*imageKey=[NSString stringWithFormat:@"PM/%@/image@%lu_%@",id,(unsigned long)applied,variant];NSString*blurKey=[NSString stringWithFormat:@"PM/%@/blur@%lu_%@",id,(unsigned long)applied,variant];
  P cover=r.get<P>(card,"cover"),blur=r.get<P>(card,"coverBlur");
  r.put(card,"coverAssetCode",r.managedString(imageKey));r.put(card,"coverBlurAssetCode",r.managedString(blurKey));
  if(r.alive(cover)){
   NSString*current=r.string(r.call(cover,"get_Code"));
   if(![current isEqualToString:imageKey]){
    r.call(cover,"CheckInitialized");
    if(r.get<bool>(cover,"loadedImage")){float duration=std::clamp(r.get<float>(self,"animationTime"),.15f,.6f);r.call(cover,"SetImageWithTransition",{"System.String","System.Single"},{r.managedString(imageKey),&duration});}
    else{r.call(cover,"SetLowResImage",{"System.String"},{r.managedString(blurKey)});r.call(cover,"set_Code",{"System.String"},{r.managedString(imageKey)});}
    log([NSString stringWithFormat:@"Content chapter cover requested: %@ lowres=%@ full=%@",id,blurKey,imageKey]);
   }
  }
  if(r.alive(blur)&&![r.string(r.call(blur,"get_Code"))isEqualToString:blurKey])r.call(blur,"set_Code",{"System.String"},{r.managedString(blurKey)});
  bool no=false;r.call(r.get<P>(card,"locked"),"SetActive",{"System.Boolean"},{&no});
  bool hasSongs=r.count(r.get<P>(info,"songs"))>0;r.call(r.get<P>(card,"play"),"set_interactable",{"System.Boolean"},{&hasSongs});
  log([NSString stringWithFormat:@"Content custom chapter cover primed: %@ key=%@",id,imageKey]);
 }
 r.stat(r.type("UnityEngine.UI","LayoutRebuilder"),"ForceRebuildLayoutImmediate",{"UnityEngine.RectTransform"},{r.get<P>(self,"chapterPanel")});
 if(hiddenChapterCards>0&&cards&&r.array_length(cards)>1){
  P panel=r.get<P>(self,"chapterPanel");std::vector<float>gaps;V3 previous{};bool havePrevious=false;
  for(uintptr_t i=0;i<r.array_length(cards);++i){P card=r.arrayAt(cards,(int)i),tr=r.call(card,"get_transform");
   for(int depth=0;depth<16;++depth){P parent=r.call(tr,"get_parent");if(!parent||parent==panel)break;tr=parent;}
   V3 position=r.unbox<V3>(r.call(tr,"get_localPosition"));if(havePrevious&&std::fabs(position.x-previous.x)>1)gaps.push_back(std::fabs(position.x-previous.x));previous=position;havePrevious=true;
  }
  if(!gaps.empty()){std::sort(gaps.begin(),gaps.end());float step=gaps[gaps.size()/2];V2 size=r.unbox<V2>(r.call(panel,"get_sizeDelta"));size.x=std::max(step,size.x-hiddenChapterCards*step);r.call(panel,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});}
 }
 syncChapterCoverFallbacks(r);
 log(@"Content ChapterSelector.Start completed");
}
void attach(Runtime&r){runtime=&r;}
bool sourceHoldGeometry(Runtime&r,P control){
 P note=r.get<P>(control,"noteInfor");auto found=extras.find(note);
 return found!=extras.end()&&found->second[@"pmRawSpeed"]!=nil;
}
bool shortSourceHold(Runtime&r,P note){
 auto it=extras.find(note);if(!currentChart||it==extras.end())return false;
 NSDictionary*source=it->second;
 if([source[@"type"] intValue]!=3||[source[@"pmFake"] boolValue]||!source[@"pmDuration"]||r.get<int>(note,"type")!=3)return false;
 float duration=r.get<float>(note,"holdTime");
 return std::isfinite(duration)&&duration>0&&duration<.22f;
}
bool customLevel(){return levelID.length>0||lastCustom;}
void avatarPulse(Runtime&r){
 struct Saved{uint32_t loader;NSString*code;bool preserveAspect;};static std::vector<Saved>saved;
 static double next=0;double now=NSDate.timeIntervalSinceReferenceDate;if(now<next)return;next=now+1;
 for(auto it=saved.begin();it!=saved.end();){if(!r.alive(target(r,it->loader))){r.gchandle_free(it->loader);it=saved.erase(it);}else ++it;}
 NSUserDefaults*d=NSUserDefaults.standardUserDefaults;bool enabled=[d boolForKey:@"phimod.avatar.enabled"];
 if(!enabled){for(auto&entry:saved){P loader=target(r,entry.loader);NSString*current=r.string(r.call(loader,"get_Code"));if([current hasPrefix:@"PM/pm_avatar/"]){r.call(loader,"set_Code",{"System.String"},{r.managedString(entry.code)});P image=r.get<P>(loader,"_image");if(r.alive(image))r.call(image,"set_preserveAspect",{"System.Boolean"},{&entry.preserveAspect});}r.gchandle_free(entry.loader);}saved.clear();return;}
 NSString*revision=[d stringForKey:@"phimod.avatar.revision"]?:@"1";
 NSString*key=[NSString stringWithFormat:@"PM/pm_avatar/image@%@",revision];
 for(const char*name:{"PlayerBarControl","StatsFrameController"}){
  P cls=r.klass(name);P objects=r.stat(r.type("UnityEngine","Object"),"FindObjectsOfType",{"System.Type"},{r.type_get_object(r.class_get_type(cls))});
  for(uintptr_t i=0;objects&&i<r.array_length(objects);++i){P owner=r.arrayAt(objects,(int)i),loader=r.get<P>(owner,"avatar");if(!r.alive(loader))continue;
   NSString*code=r.string(r.call(loader,"get_Code"));bool tracked=false;
   for(auto&entry:saved)if(target(r,entry.loader)==loader){tracked=true;if(![code hasPrefix:@"PM/pm_avatar/"])entry.code=code;break;}
   r.call(loader,"CheckInitialized");P avatarImage=r.get<P>(loader,"_image");
   if(!tracked){bool preserve=r.alive(avatarImage)?r.unbox<bool>(r.call(avatarImage,"get_preserveAspect")):false;saved.push_back({r.gchandle_new(loader,false),code,preserve});}
   if(r.alive(avatarImage)){bool preserve=true;if(!r.unbox<bool>(r.call(avatarImage,"get_preserveAspect")))r.call(avatarImage,"set_preserveAspect",{"System.Boolean"},{&preserve});}
   if(![code isEqualToString:key]){r.call(loader,"CheckInitialized");r.call(loader,"set_Code",{"System.String"},{r.managedString(key)});log(@"Custom avatar resource requested");}
  }
 }
}
void pulse(){if(!runtime||playing||![NSThread isMainThread])return;try{capture(*runtime);avatarPulse(*runtime);}catch(const std::exception&e){static std::string previous;if(previous!=e.what()){previous=e.what();log([NSString stringWithFormat:@"Avatar update: %s",e.what()]);}} }

NSDictionary*cachedOfficialSnapshot(){@synchronized(PMContentStore.shared){return officialCache;}}
bool isMainlineChapter(NSString*code){if(![code isKindOfClass:NSString.class]||![code hasPrefix:@"MainStory"])return NO;for(NSDictionary*c in originalChapters)if([c[@"chapterCode"] isEqualToString:code])return YES;return NO;}
bool isMainlineSong(NSString*songID){if(!officialCache)pulse();if(![songID isKindOfClass:NSString.class]||!officialCache)return NO;for(NSDictionary*c in officialCache[@"chapters"]){if(!isMainlineChapter(c[@"chapterCode"]))continue;for(NSDictionary*s in c[@"songInfo"][@"songs"])if([s[@"songsId"] isEqualToString:songID])return YES;}return NO;}
void refreshMainlineAccess(Runtime&r){if(playing||!baseline)return;bool desired=PMSettingBool("mainlineUnlock");if(desired!=appliedMainline)apply(r);}
NSDictionary*officialSnapshot(){pulse();return @{@"songBase":baseline ?: @{},@"chapters":originalChapters ?: @[],@"applied":@(applied),@"revision":@(PMContentStore.shared.revision),@"playing":@(playing)};}
NSDictionary*command(NSString*action,NSString*identifier,int slot){
 if(!runtime)return @{ @"ok":@NO,@"message":@"璇峰厛绛夊緟娓告垙鍔犺浇瀹屾垚"};
 if(playing)return @{ @"ok":@NO,@"message":@"Cannot change chart library or chapter during gameplay."};
  if(![NSThread isMainThread])return @{ @"ok":@NO,@"message":@"Submit this operation on the main thread."};
 if(![@[@"apply",@"chapter",@"play"] containsObject:action])return @{ @"ok":@NO,@"message":@"Unknown chart-library action."};
 @try{try{
  auto&r=*runtime;log([NSString stringWithFormat:@"Content command begin: %@ %@",action,identifier]);
  apply(r);if(!baseline)throw std::runtime_error("Game library is not ready");
  log(@"Content references published and read back");
  const char*scene="ChapterSelector";
  if(![action isEqualToString:@"apply"]){
   NSString*chapterID=identifier;
   if([action isEqualToString:@"play"]){
    NSDictionary*chosen=nil;for(NSDictionary*s in [PMContentStore.shared snapshot][@"songs"])if([s[@"id"]isEqualToString:identifier]){chosen=s;break;}
    if(!chosen)throw std::runtime_error("Custom chart no longer exists");
    chapterID=chosen[@"targetChapter"] ?: @"pm_local";pendingSong=groupFor(identifier);pendingSlot=std::clamp(slot,0,3);
   }
   P chapter=r.call(r.mainGame(),"GetChapterWithCode",{"System.String"},{r.managedString(chapterID)});
   if(!chapter)throw std::runtime_error("Requested chapter does not exist");
   P songs=r.get<P>(r.get<P>(chapter,"songInfo"),"songs");
   if(r.count(songs)==0)throw std::runtime_error("Chapter is empty; import charts before opening it");
   r.setStaticValue<P>(r.klass("GameInformation"),"nowChapterCode","System.String",r.managedString(chapterID));
   r.setStaticValue<P>(r.klass("GameInformation"),"nextScene","System.String",r.string_new("ChapterSelector"));
   log([@"Content navigation fields verified: " stringByAppendingString:chapterID]);scene="SongSelector";
  }
  log([NSString stringWithFormat:@"Content LoadScene begin: %s",scene]);
  r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"LoadScene",{"System.String"},{r.string_new(scene)});
  log(@"Content LoadScene returned");return @{ @"ok":@YES,@"message":@"宸叉彁浜ゅ埌鍘熺増閫夋洸娴佺▼"};
 }catch(const std::exception&e){pendingSong=nil;log([NSString stringWithFormat:@"Content command failed: %s",e.what()]);return @{ @"ok":@NO,@"message":[NSString stringWithUTF8String:e.what()]};}
 }@catch(NSException*e){pendingSong=nil;log([NSString stringWithFormat:@"Content command exception: %@ %@",e.name,e.reason]);return @{ @"ok":@NO,@"message":e.reason ?: e.name};}
}
// Only the selected song's expensive image/music requests are completed after
// settling. Blur requests continue through the original synchronous path.
namespace {
double selectorNow(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
void observeSelector(Runtime&r,P selector){
 int index=r.get<int>(selector,"nowSong"),slot=r.get<int>(selector,"nowLevel");float position=r.get<float>(selector,"nowSongSelectorValue");
 // Native transition flags can outlive positional movement while assets load.
 // Settle on actual position/selection changes and touches, not asset-dependent flags.
 bool moving=r.unbox<int>(r.stat(r.type("UnityEngine","Input"),"get_touchCount"))>0;
 bool changed=index!=loadingSong||slot!=loadingSlot||std::fabs(position-loadingPosition)>.001f;
 if(changed||moving)selectionChangedAt=selectorNow();
 selectorDragging=moving;loadingPosition=position;loadingSong=index;loadingSlot=slot;
 selectedAssetIDs.clear();P items=r.call(selector,"get_SongItems");if(index<0||index>=r.count(items))return;
 P item=r.at(items,index),song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));
 try{if(changed&&selectorSongIDs.count(group.UTF8String?:"")){P cover=r.get<P>(item,"cover");NSString*blur=r.string(r.get<P>(item,"coverBlurAssetCode"));
  if(blur.length&&r.alive(cover)&&!r.get<bool>(cover,"loadedImage")&&!r.get<bool>(cover,"loadedLowResImage")){
   r.call(cover,"CheckInitialized");r.call(cover,"SetLowResImage",{"System.String"},{r.managedString(blur)});
  }
 }}catch(const std::exception&e){log([NSString stringWithFormat:@"Selector low-res preview failed (full cover continues): %s",e.what()]);}
 if(group.length)selectedAssetIDs.insert(group.UTF8String);
 auto found=variants.find(group.UTF8String?:"");if(found!=variants.end()){auto member=found->second.find(slot);if(member!=found->second.end()){NSString*id=member->second[@"id"];if(id.length)selectedAssetIDs.insert(id.UTF8String);}}
 for(const char*field:{"coverAssetCode"}){NSString*kind=nil,*id=keyID(r.string(r.get<P>(item,field)),&kind);if(id.length)selectedAssetIDs.insert(id.UTF8String);}
 P coverLoader=r.get<P>(item,"cover");if(r.alive(coverLoader)){NSString*kind=nil,*id=keyID(r.string(r.call(coverLoader,"get_Code")),&kind);if(id.length)selectedAssetIDs.insert(id.UTF8String);}
 // Preview bookkeeping must not abort completion of an already-selected cover.
 try{P preview=r.get<P>(item,"previewClipPlayer");if(r.alive(preview)){NSString*kind=nil,*id=keyID(r.string(r.get<P>(preview,"clipCode")),&kind);if(id.length)selectedAssetIDs.insert(id.UTF8String);}}catch(const std::exception&e){static bool reported=false;if(!reported){reported=true;log([NSString stringWithFormat:@"Selector preview key lookup failed (cover continues): %s",e.what()]);}}
}
void completeSelectorAsset(Runtime&r,P asset){
 auto found=selectorAssets.find(asset);if(found==selectorAssets.end())return;
 uint32_t root=found->second.root;bool music=found->second.music;double began=selectorNow();selectorAssets.erase(found);
 int references=r.get<int>(asset,"refCount");
 completingSelectorAsset=true;
 try{if(references>0){assetConstructor(r,asset,r.get<P>(asset,"key"));r.put(asset,"refCount",references);}}
 catch(...){completingSelectorAsset=false;r.gchandle_free(root);throw;}
 completingSelectorAsset=false;r.gchandle_free(root);
 log([NSString stringWithFormat:@"Content selected %@ request completed in %.1f ms",music?@"audio":@"cover",(selectorNow()-began)*1000]);
}
}
void selectorLoadingBegin(Runtime&r,P selector){
 if(playing||r.get<bool>(selector,"exit"))return;
 if(target(r,loadingSelector)!=selector){selectorLoadingEnd(r,false);loadingSelector=r.gchandle_new(selector,false);selectionChangedAt=selectorNow();loadingSong=-1;selectorLibraryRevision=NSUIntegerMax;}
 NSUInteger revision=PMContentStore.shared.revision;
 if(selectorLibraryRevision!=revision){selectorSongIDs.clear();for(NSDictionary*song in [PMContentStore.shared snapshot][@"songs"]){for(NSString*field in @[@"id",@"groupId"]){NSString*id=song[field];if(id.length)selectorSongIDs.insert(id.UTF8String);}}selectorLibraryRevision=revision;}
}
void selectorLoadingFrame(Runtime&r,P selector){
 if(target(r,loadingSelector)!=selector||r.get<bool>(selector,"exit"))return;
 observeSelector(r,selector);
 if(selectorDragging||selectorNow()-selectionChangedAt<.30)return;
 // At most one expensive upload/decode per frame; cover before preview audio.
 for(bool music:{false,true})for(auto&entry:selectorAssets)if(entry.second.music==music&&selectedAssetIDs.count(entry.second.identifier)){
  P asset=entry.first;completeSelectorAsset(r,asset);return;
 }
}
void selectorLoadingEnd(Runtime&r,bool finishSelected){
 if(finishSelected&&r.alive(target(r,loadingSelector)))observeSelector(r,target(r,loadingSelector));
 if(loadingSelector)r.gchandle_free(loadingSelector);loadingSelector=0;
 std::vector<P>remaining;for(auto&entry:selectorAssets)remaining.push_back(entry.first);
 for(P asset:remaining){auto found=selectorAssets.find(asset);if(found==selectorAssets.end())continue;
  if(finishSelected&&selectedAssetIDs.count(found->second.identifier)){completeSelectorAsset(r,asset);continue;}
  // Consumers awaiting a cancelled scene request must not wait forever. Remove
  // it from AssetStore too, so returning to this song creates a fresh request.
  r.put(asset,"<IsDone>k__BackingField",true);r.put(asset,"<IsFailed>k__BackingField",true);assetRelease(r,asset,true);
 }
 selectorSongIDs.clear();selectedAssetIDs.clear();loadingSong=-1;loadingSlot=-1;selectorDragging=true;
}
// Native difficulty bars assume a continuous EZ..AT prefix. Custom groups may be sparse.
void selectorFrame(Runtime&r,P selector){
 static P lastSelector=nullptr,lastItem=nullptr;static int lastLevel=-1,lastMask=0;
 if(r.get<bool>(selector,"exit")||r.get<bool>(selector,"isMoving")){lastItem=nullptr;return;}
 P items=r.call(selector,"get_SongItems");int n=r.count(items),index=r.get<int>(selector,"nowSong");
 bool launch=false;
 if(pendingSong.length){for(int i=0;i<n;++i){P item=r.at(items,i),song=r.get<P>(item,"songInfo");if([r.string(r.get<P>(song,"songsId"))isEqualToString:pendingSong]){index=i;r.put(selector,"nowSong",i);r.put(selector,"nowLevel",pendingSlot);launch=true;break;}}}
 if(index<0||index>=n)return;
 P item=r.at(items,index),song=r.get<P>(item,"songInfo");NSString*identifier=r.string(r.get<P>(song,"songsId"));
 auto group=variants.find(identifier.UTF8String?:"");
 if([identifier hasPrefix:@"pm_"]&&group!=variants.end()&&!group->second.empty()){
  int mask=0,extent=0;for(auto&entry:group->second)if(entry.first>=0&&entry.first<4){mask|=1<<entry.first;extent=std::max(extent,entry.first+1);}
  if(mask){
   int level=r.get<int>(selector,"nowLevel"),selected=level;
   if(level<0||level>=4||!(mask&(1<<level))){selected=-1;for(int i=std::min(level,3);i>=0;--i)if(mask&(1<<i)){selected=i;break;}if(selected<0)for(int i=0;i<4;++i)if(mask&(1<<i)){selected=i;break;}}
   // Preserve original slot indices: AT must remain slot 3 for assets, records and rules.
   // Match Android songItemCtor: lower placeholders occupy three slots,
   // and AT uses the normal four-slot width, not the old two-slot width.
   int displayCount=std::max(3,extent),infoWidth=displayCount>=4?100:115;
   bool layoutChanged=r.get<int>(item,"<PlayableLevelCount>k__BackingField")!=displayCount||r.get<int>(item,"<SelectorTargetWidth>k__BackingField")!=infoWidth;
   r.put(item,"<PlayableLevelCount>k__BackingField",displayCount);
   r.put(item,"<SelectorTargetWidth>k__BackingField",infoWidth);
   r.put(selector,"levelNum",displayCount);
   if(lastSelector!=selector||lastItem!=item||lastLevel!=selected||lastMask!=mask||selected!=level||layoutChanged||launch){
    r.put(selector,"nowLevel",selected);r.call(selector,"SetLevel",{"System.Int32"},{&selected});
    P bar=r.get<P>(selector,"levelBarController");
    if(bar){r.call(bar,"UpdateInfoImmediately",{"SongSelectorItem"},{item});P infos=r.get<P>(bar,"levelInfos");
     for(int i=0;infos&&i<4&&uintptr_t(i)<r.array_length(infos);++i){P info=r.arrayAt(infos,i);if(!info)continue;
      // Match Android: lower slots retain their positions; absent charts display '-'.
      bool visible=i<3||(mask&(1<<i));r.call(info,"SetActive",{"System.Boolean"},{&visible});
      if(!(mask&(1<<i))){NSString*label=@[@"EZ",@"HD",@"IN",@"AT"][i];r.call(info,"HideInfo",{"System.String"},{r.managedString(label)});}
     }
    }
    lastSelector=selector;lastItem=item;lastLevel=selected;lastMask=mask;
   }
  }
 }else{lastItem=nullptr;if(launch){int level=pendingSlot;r.call(selector,"SetLevel",{"System.Int32"},{&level});}}
 if(launch){pendingSong=nil;r.call(selector,"NormalStart");}
}

void levelBegin(Runtime&r){selectorLoadingEnd(r,true);playing=true;if(chapterSelectorRoot){r.gchandle_free(chapterSelectorRoot);chapterSelectorRoot=0;}P info=r.get<P>(r.mainGame(),"levelStartInfo");NSString*id=info?r.string(r.get<P>(info,"songsId")):@"";levelID=[PMContentStore.shared asset:id]?id:nil;lastCustom=levelID.length>0;}
void levelEnd(Runtime&r){playing=false;levelID=nil;lastCustom=false;pendingSong=nil;if(chapterSelectorRoot){r.gchandle_free(chapterSelectorRoot);chapterSelectorRoot=0;}clearVisuals(r);}
bool assetConstructor(Runtime&r,P self,P key){NSString*kind=nil,*identifier=keyID(r.string(key),&kind);if(!identifier)return false;r.put(self,"key",key);r.put(self,"refCount",1);
 if(loadingSelector&&!completingSelectorAsset&&!playing&&selectorSongIDs.count(identifier.UTF8String)&&([kind isEqualToString:@"image"]||[kind isEqualToString:@"music"])){
  auto cached=assets.find(r.string(key).UTF8String);
  if(cached==assets.end()||!r.alive(target(r,cached->second))){
   r.put<P>(self,"obj",nullptr);r.put(self,"<IsDone>k__BackingField",false);r.put(self,"<IsFailed>k__BackingField",false);
   selectorAssets[self]={r.gchandle_new(self,false),identifier.UTF8String,[kind isEqualToString:@"music"]!=NO};return true;
  }
 }
 try{std::string cacheKey=r.string(key).UTF8String;P obj=nullptr;auto found=assets.find(cacheKey);if(found!=assets.end())obj=target(r,found->second);if(!r.alive(obj)){NSString*folder=[PMContentStore.shared asset:identifier];if([kind isEqualToString:@"chart"]){NSString*json=[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@"chart-native.json"] encoding:NSUTF8StringEncoding error:nil];if(!json)throw std::runtime_error("Custom chart not found");log([NSString stringWithFormat:@"Content chart text ready: chars=%lu",(unsigned long)json.length]);obj=r.object_new(r.type("UnityEngine","TextAsset"));uint32_t h=r.gchandle_new(obj,false);try{r.call(obj,".ctor",{"System.String"},{r.managedString(json)});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);}else if([kind isEqualToString:@"music"]){NSString*m4a=[folder stringByAppendingPathComponent:@"music.m4a"];NSString*caf=[folder stringByAppendingPathComponent:@"music.caf"];obj=audio(r,[NSFileManager.defaultManager fileExistsAtPath:m4a]?m4a:caf);}else obj=image(r,[identifier isEqualToString:@"pm_avatar"]?[[PMContentStore.shared asset:identifier]stringByAppendingPathComponent:@"image.png"]:pmunlock::coverPath(r,identifier),[kind isEqualToString:@"blur"]);assets[cacheKey]=r.gchandle_new(obj,false);}refs[self]=cacheKey;users[cacheKey]++;r.put(self,"obj",obj);r.put(self,"<IsDone>k__BackingField",true);r.put(self,"<IsFailed>k__BackingField",false);if([kind isEqualToString:@"image"])try{syncChapterCoverFallbacks(r);}catch(const std::exception&e){log([NSString stringWithFormat:@"Content chapter cover fallback failed: %s",e.what()]);}log([@"Content asset loaded: " stringByAppendingString:r.string(key)]);}catch(const std::exception&e){r.put<P>(self,"obj",nullptr);r.put(self,"<IsDone>k__BackingField",true);r.put(self,"<IsFailed>k__BackingField",true);log([NSString stringWithFormat:@"Content asset failed: %@ (%s)",r.string(key),e.what()]);}return true;}
bool assetRelease(Runtime&r,P self,bool force){
 NSString*kind=nil;P key=r.get<P>(self,"key");if(!keyID(r.string(key),&kind))return false;
 int n=r.get<int>(self,"refCount");if(!force&&n>1){r.put(self,"refCount",n-1);return true;}
 auto pending=selectorAssets.find(self);if(pending!=selectorAssets.end()){r.gchandle_free(pending->second.root);selectorAssets.erase(pending);}
 auto it=refs.find(self);
 if(it!=refs.end()){
  auto k=it->second;refs.erase(it);
  if(--users[k]<=0){auto asset=assets.find(k);if(asset!=assets.end()){
   P obj=target(r,asset->second);if(r.alive(obj))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{obj});
   auto tex=textures.find(obj);if(tex!=textures.end()){P t=target(r,tex->second);if(r.alive(t))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{t});r.gchandle_free(tex->second);textures.erase(tex);}
   r.gchandle_free(asset->second);assets.erase(asset);
  }users.erase(k);}
 }
 r.put<P>(self,"obj",nullptr);r.put(self,"refCount",0);
 P klass=r.klass("AssetStore");r.runtime_class_init(klass);P contents=nullptr;r.field_static_get_value(r.class_get_field_from_name(klass,"contents"),&contents);
 if(contents&&r.unbox<bool>(r.call(contents,"ContainsKey",{"System.String"},{key}))&&r.call(contents,"get_Item",{"System.String"},{key})==self)r.call(contents,"Remove",{"System.String"},{key});
 log([NSString stringWithFormat:@"Content custom release (%@): %@",force?@"ReleaseResource":@"Release",r.string(key)]);return true;
}
void levelInfo(Runtime&r,P song,int slot,P info){NSString*id=r.string(r.get<P>(song,"songsId"));NSDictionary*custom=songFor(id,slot);if(!custom||!info)return;NSString*identifier=custom[@"id"];for(const auto&entry:std::vector<std::pair<const char*,NSString*>>{{"songsId",identifier},{"songsName",custom[@"title"] ?: @""},{"composer",custom[@"composer"] ?: @""},{"charter",custom[@"charter"] ?: @""},{"illustrator",custom[@"illustrator"] ?: @""},{"songsDifficulty",[custom[@"difficulty"] description]}})r.put(info,entry.first,r.managedString(entry.second));for(auto pair:std::vector<std::pair<const char*,const char*>>{{"musicAddressableKey","music"},{"chartAddressableKey","chart"},{"illustrationKey","image"}}){NSString*k=[NSString stringWithFormat:@"PM/%@/%s@%lu",identifier,pair.second,(unsigned long)PMContentStore.shared.revision];r.put(info,pair.first,r.managedString(k));}}
void beforeChart(Runtime&r,P level){if(!levelID.length)return;NSString*path=[[PMContentStore.shared asset:levelID]stringByAppendingPathComponent:@"chart.json"];NSData*d=[NSData dataWithContentsOfFile:path];currentChart=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;if(!currentChart)throw std::runtime_error("Custom visual chart missing");resourceSubdir=@"";for(NSDictionary*s in [PMContentStore.shared snapshot][@"songs"])if([s[@"id"]isEqualToString:levelID])resourceSubdir=s[@"resourceRoot"] ?: @"";beforeInformation(r,level);}
void afterChart(Runtime&r,P level){clearHud(r);if(!currentChart)return;hudLevel=r.gchandle_new(level,false);
 // Match Android's zOrder/index ranking instead of treating zOrder as a
 // native sortingOrder offset (negative values otherwise fall behind BG).
 NSArray*sourceLines=currentChart[@"judgeLineList"];std::vector<int>ordered;
 inertLineVisuals.clear();uiControlLines.clear();rpeIntroRetired=false;reportedLineAlphaCorrections.clear();
 for(NSUInteger i=0;i<sourceLines.count;++i){
  ordered.push_back((int)i);NSDictionary*source=sourceLines[i],*decor=source[@"pmDecor"];
  NSString*texture=decor[@"Texture"];NSArray*alpha=source[@"judgeLineDisappearEvents"];
  NSString*attachment=[decor[@"attachUI"]isKindOfClass:NSString.class]?[decor[@"attachUI"]lowercaseString]:@"";
  if([@[@"pause",@"combonumber",@"combo",@"score",@"bar",@"name",@"level"]containsObject:attachment]){
   uiControlLines.insert((int)i);
   int code=(int)[@[@"pause",@"combonumber",@"combo",@"score",@"bar",@"name",@"level"]indexOfObject:attachment]+1;hudLines[code]=(int)i;
   log([NSString stringWithFormat:@"Content UI control line excluded from chart rendering: line=%lu attachUI=%@",(unsigned long)i,attachment]);
  }
  // Keep every native line and its index: invisible lines can still be parents
  // or note lanes. Only skip redundant MOD sprite/scale/color work for empty,
  // permanently transparent standard-line visuals (no storyboard/text content).
  bool inert=decor&&![source[@"notesAbove"]count]&&![source[@"notesBelow"]count]&&![decor[@"textEvents"]count]&&![decor[@"scaleXEvents"]count]&&![decor[@"scaleYEvents"]count]&&![decor[@"colorEvents"]count]&&(!texture.length||[texture isEqualToString:@"line.png"])&&alpha.count;
  if(inert)for(NSDictionary*event in alpha){double a=[event[@"start"]doubleValue],b=[event[@"end"]doubleValue];if(!std::isfinite(a)||!std::isfinite(b)||a>0||b>0){inert=false;break;}}
  if(inert)inertLineVisuals.insert((int)i);
 }
 log([NSString stringWithFormat:@"Content line visuals: total=%lu inert=%lu (native indices preserved)",(unsigned long)sourceLines.count,(unsigned long)inertLineVisuals.size()]);
 std::stable_sort(ordered.begin(),ordered.end(),[&](int a,int b){return [sourceLines[a][@"pmDecor"][@"zOrder"] integerValue]<[sourceLines[b][@"pmDecor"][@"zOrder"] integerValue];});
 storyOrders.resize(ordered.size());
 for(size_t rank=0;rank<ordered.size();++rank)storyOrders[ordered[rank]]=3+int(rank)*2;
 storyHoldOrder=std::max(1028,5+int(ordered.size())*2);storyNoteOrder=storyHoldOrder+2;
sourceFloors.clear();int sourceIndex=0;
 for(NSDictionary*sourceLine in currentChart[@"judgeLineList"]){
  double secondsPerTick=60.0/(32.0*[sourceLine[@"bpm"] doubleValue]);
  auto&track=sourceFloors[sourceIndex++];
  if(!std::isfinite(secondsPerTick)||secondsPerTick<=0)continue;
  for(NSDictionary*event in sourceLine[@"speedEvents"])track.push_back({[event[@"startTime"] doubleValue]*secondsPerTick,[event[@"endTime"] doubleValue]*secondsPerTick,[event[@"value"] doubleValue],[event[@"floorPosition"] doubleValue]});
  std::stable_sort(track.begin(),track.end(),[](const auto&a,const auto&b){return a.start<b.start;});
 }
// Native SetInformation may reorder note lists. Bind before that call and
// restore timing by object identity, never by its post-sort array position.
for(const auto&entry:extras){P note=entry.first;NSDictionary*source=entry.second;
 if(source[@"pmTime"]){float time=[source[@"pmTime"] floatValue];if(std::isfinite(time))r.put(note,"realTime",time);}
 // A Tap converted into a Hold must retain the mode's generated duration.
 if([source[@"type"] intValue]==3&&r.get<int>(note,"type")==3&&source[@"pmDuration"]){float duration=[source[@"pmDuration"] floatValue];if(std::isfinite(duration)&&duration>=0)r.put(note,"holdTime",duration);}
}
}
void beforeInformation(Runtime&r,P level){
 if(!currentChart){extras.clear();extrasBoundChart=nullptr;return;}
 P chart=r.get<P>(level,"chart");if(chart==extrasBoundChart)return;
 P lines=r.get<P>(chart,"judgeLineList");NSArray*data=currentChart[@"judgeLineList"];
 if(r.count(lines)!=(int)data.count)throw std::runtime_error("Custom source/native line count mismatch");
 // 4.0.3 sorts by floorPosition BEFORE SetCodeForNote and SetInformation.
 // List.Sort is not stable for simultaneous Tap/Hold notes. Match serialized
 // values, not list positions, while holdTime is still in chart ticks and
 // before unified-note modes mutate type/speed/duration.
 using Key=std::tuple<int,int,float,float,float,float>;
 std::map<P,NSDictionary*>bound;size_t reordered=0;
 for(int i=0;i<(int)data.count;++i){P line=r.at(lines,i);
  for(NSString*side in @[@"notesAbove",@"notesBelow"]){
   P list=r.get<P>(line,side.UTF8String);NSMutableArray*real=[NSMutableArray new];
   std::map<Key,std::vector<NSDictionary*>>sources;
   for(NSDictionary*source in data[i][side])if(![source[@"pmFake"]boolValue]){
    [real addObject:source];Key key{[source[@"type"]intValue],[source[@"time"]intValue],[source[@"positionX"]floatValue],[source[@"holdTime"]floatValue],[source[@"speed"]floatValue],[source[@"floorPosition"]floatValue]};sources[key].push_back(source);
   }
   if(r.count(list)!=(int)real.count)throw std::runtime_error("Custom source/native note count mismatch");
   std::map<Key,size_t>used;
   for(int j=0;j<(int)real.count;++j){P note=r.at(list,j);
    Key key{r.get<int>(note,"type"),r.get<int>(note,"time"),r.get<float>(note,"positionX"),r.get<float>(note,"holdTime"),r.get<float>(note,"speed"),r.get<float>(note,"floorPosition")};
    auto found=sources.find(key);size_t&next=used[key];
    if(found==sources.end()||next>=found->second.size())throw std::runtime_error("Custom note identity mismatch before source binding");
    NSDictionary*source=found->second[next++];bound[note]=source;if(source!=real[j])++reordered;
   }
  }
 }
 extras.swap(bound);extrasBoundChart=chart;
 log([NSString stringWithFormat:@"Content source binding: notes=%lu reordered=%lu (serialized identity, before mode edits)",(unsigned long)extras.size(),(unsigned long)reordered]);
}

namespace {
double scalar(id value,double fallback=0){return [value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:fallback;}
phimod::rpe::Event visualEvent(NSDictionary*v,int channel=-1){phimod::rpe::Event e;e.s=scalar(v[@"startTime"]);e.e=scalar(v[@"endTime"]);id a=v[@"start"],b=v[@"end"];if(channel>=0){a=[a isKindOfClass:NSArray.class]&&[a count]>channel?a[channel]:@255;b=[b isKindOfClass:NSArray.class]&&[b count]>channel?b[channel]:@255;}e.a=scalar(a);e.b=scalar(b);if(channel>=0){e.a/=255;e.b/=255;}e.easing=(int)scalar(v[@"easingType"],1);e.left=scalar(v[@"easingLeft"],0);e.right=scalar(v[@"easingRight"],1);NSArray*p=v[@"bezierPoints"];if([v[@"bezier"] boolValue]&&p.count==4){e.bezier=true;for(int i=0;i<4;++i)e.points[i]=scalar(p[i]);}return e;}
NSDictionary*eventAt(NSArray*events,double time,double units=1){
 NSUInteger lo=0,hi=events.count;
 while(lo<hi){NSUInteger mid=lo+(hi-lo)/2;if(scalar(events[mid][@"startTime"])*units<=time)lo=mid+1;else hi=mid;}
 return lo?events[lo-1]:nil;
}
// Both standard and textured RPE lines use the same native-tick alpha track.
float sourceLineAlpha(NSArray*events,double now,double bpm){
 if(!std::isfinite(bpm)||bpm<=0)return 0;
 double secondsPerTick=60.0/(32.0*bpm);NSDictionary*event=eventAt(events,now,secondsPerTick);
 if(!event)return 0;
 double start=scalar(event[@"startTime"])*secondsPerTick,end=scalar(event[@"endTime"])*secondsPerTick;
 double t=end>start?std::clamp((now-start)/(end-start),0.,1.):1.;
 double value=scalar(event[@"start"])+(scalar(event[@"end"])-scalar(event[@"start"]))*t;
 return std::isfinite(value)?float(std::clamp(value,0.,1.)):0.f;
}
double trackValue(NSArray*a,double now,double fallback,int channel=-1){NSDictionary*last=eventAt(a,now);return last?visualEvent(last,channel).value(now):fallback;}

#include "PMRPEHudRuntime.inc"

float notePerspectiveWidth(Runtime&r,NSDictionary*decor,float now){
 if(![decor[@"inclineEvents"]count]||std::fabs(trackValue(decor[@"inclineEvents"],now,0))<1e-6)return 0;
 // Cache within a Unity frame, including real and fake notes, without scene scans.
 static int cachedFrame=-1;static float width=0;
 int frame=r.unbox<int>(r.stat(r.type("UnityEngine","Time"),"get_frameCount"));
 if(frame!=cachedFrame){cachedFrame=frame;width=0;P camera=r.stat(r.type("UnityEngine","Camera"),"get_main");if(r.alive(camera))width=2*r.unbox<float>(r.call(camera,"get_orthographicSize"))*std::min(16.f/9.f,r.unbox<float>(r.call(camera,"get_aspect")));}
 return width;
}
double control(NSDictionary*d,NSString*key,double distance){
 NSArray*points=d[key];if(!points.count)return [key isEqualToString:@"skewControl"]?0:1;
 auto found=controlCache.find(points);
 if(found==controlCache.end()){
  NSString*value=[key substringToIndex:key.length-7];std::vector<ControlPoint>cached;cached.reserve(points.count);
  for(NSDictionary*p in points)cached.push_back({scalar(p[@"x"]),scalar(p[value],[key isEqualToString:@"skewControl"]?0:1),(int)scalar(p[@"easing"],1)});
  std::stable_sort(cached.begin(),cached.end(),[](const auto&a,const auto&b){return a.x<b.x;});
  found=controlCache.emplace(points,std::move(cached)).first;
 }
 const auto&track=found->second;
 if(distance<=track.front().x)return track.front().value;
 auto next=std::lower_bound(track.begin(),track.end(),distance,[](const auto&p,double x){return p.x<x;});
 if(next==track.end())return track.back().value;
 const auto&a=*(next-1);const auto&b=*next;double q=b.x>a.x?(distance-a.x)/(b.x-a.x):1;
 return a.value+(b.value-a.value)*phimod::rpe::ease(b.easing,q);
}
#include "PMRPESkewRuntime.inc"

P addComponent(Runtime&r,P go,P type){return r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(type))});}
P graphic(Runtime&r,P go){P list=r.children(go,r.type("UnityEngine","SpriteRenderer"));return list&&r.array_length(list)?r.arrayAt(list,0):nullptr;}
float floor(Runtime&r,P info,int index){P a=r.get<P>(info,"floorPositions");return a&&index>=0&&uintptr_t(index)<r.array_length(a)?r.unbox<float>(r.arrayAt(a,index)):0;}
double sourceFloor(int index,double now,double fallback){auto it=sourceFloors.find(index);return it==sourceFloors.end()?fallback:phimod::rpeFloor(it->second,now,fallback);}

NSString*storyTexturePath(NSString*name){
 if(![name isKindOfClass:NSString.class]||!name.length)return nil;
 name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
 if(name.isAbsolutePath)return nil;
 for(NSString*part in [name componentsSeparatedByString:@"/"])if([part isEqualToString:@".."])return nil;
 NSString*root=[[PMContentStore.shared asset:levelID]stringByStandardizingPath];
 if(!root.length)return nil;
 NSString*prefix=[root stringByAppendingString:@"/"];
 for(NSString*base in @[[root stringByAppendingPathComponent:resourceSubdir?:@""],root]){
  NSString*path=[[base stringByAppendingPathComponent:name]stringByStandardizingPath];
  if([path hasPrefix:prefix]&&[NSFileManager.defaultManager fileExistsAtPath:path])return path;
 }
 if(!storyIndexed){storyFiles=[NSFileManager.defaultManager subpathsOfDirectoryAtPath:root error:nil];storyIndexed=true;}
 NSString*match=nil;
 for(NSString*rel in storyFiles){
  BOOL matches=[rel caseInsensitiveCompare:name]==NSOrderedSame||[rel.lowercaseString hasSuffix:[@"/" stringByAppendingString:name.lowercaseString]];
  if(!matches)continue;
  NSString*path=[[root stringByAppendingPathComponent:rel]stringByStandardizingPath];BOOL dir=NO;
  if(![path hasPrefix:prefix]||![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&dir]||dir)continue;
  if(match)return nil; // Ambiguous names must not pick an unrelated image.
  match=path;
 }
 return match;
}
void updateStory(Runtime&r,int index,P line,P nativeRenderer,NSDictionary*d,NSArray*lineAlpha,double bpm,float now,P progress,Color color,int order){
 bool hasText=[d[@"textEvents"] count]>0;
 NSString*texture=[d[@"Texture"] isKindOfClass:NSString.class]?d[@"Texture"]:nil;
 if(!hasText&&(!texture.length||[texture isEqualToString:@"line.png"]))return;
 color.a=sourceLineAlpha(lineAlpha,now,bpm);
 auto found=storyVisuals.find(index);
 bool hideNative=false;r.call(nativeRenderer,"set_enabled",{"System.Boolean"},{&hideNative});
 if(color.a<=0){
  if(found!=storyVisuals.end()&&found->second.visible){bool no=false;r.call(found->second.go,"SetActive",{"System.Boolean"},{&no});found->second.visible=false;}
  return;
 }

 if(!storyFrameCamera){storyFrameCamera=r.stat(r.type("UnityEngine","Camera"),"get_main");if(!r.alive(storyFrameCamera))return;storyFrameWidth=2*r.unbox<float>(r.call(storyFrameCamera,"get_orthographicSize"))*std::min(16.f/9.f,r.unbox<float>(r.call(storyFrameCamera,"get_aspect")));}
 if(found==storyVisuals.end()){
  double clock=NSDate.timeIntervalSinceReferenceDate;
  auto retry=storyRetry.find(index);if(retry!=storyRetry.end()&&clock<retry->second)return;
  P createdRoot=nullptr;
  try{
   P camera=storyFrameCamera;
   if(!r.alive(camera))throw std::runtime_error("Storyboard camera not ready");
   float width=storyFrameWidth;
   if(!std::isfinite(width)||width<=0)throw std::runtime_error("Invalid storyboard viewport");
   StoryVisual v;v.text=hasText;
   P sprite=nullptr;
   if(!hasText){
    NSString*path=storyTexturePath(texture);
    if(!path)throw std::runtime_error("Storyboard texture missing or ambiguous");
    NSArray*a=d[@"anchor"];V2 anchor{.5,.5};if([a isKindOfClass:NSArray.class]&&a.count==2){anchor.x=scalar(a[0],.5);anchor.y=scalar(a[1],.5);}
    NSString*key=[NSString stringWithFormat:@"%@|%.9g|%.9g",path,anchor.x,anchor.y];
    auto cached=storySprites.find(key.UTF8String);
    if(cached!=storySprites.end())sprite=cached->second;
    else{sprite=image(r,path,false,true,anchor);keep(r,sprite);auto t=textures.find(sprite);if(t!=textures.end()){visualRoots.push_back(t->second);textures.erase(t);}storySprites[key.UTF8String]=sprite;}
   }
   v.go=r.object_new(r.type("UnityEngine","GameObject"));keep(r,v.go);createdRoot=v.go;
   r.call(v.go,".ctor",{"System.String"},{r.string_new(hasText?"PhiMod Story Text":"PhiMod Story Image")});
   v.tr=r.call(v.go,"get_transform");
   int layer=r.unbox<int>(r.call(r.call(line,"get_gameObject"),"get_layer"));r.call(v.go,"set_layer",{"System.Int32"},{&layer});
   int sorting=r.unbox<int>(r.call(nativeRenderer,"get_sortingLayerID"));
   if(hasText){
    v.canvas=addComponent(r,v.go,r.type("UnityEngine","Canvas"));int mode=2;bool yes=true,no=false;
    r.call(v.canvas,"set_renderMode",{"UnityEngine.RenderMode"},{&mode});r.call(v.canvas,"set_worldCamera",{"UnityEngine.Camera"},{camera});
    r.call(v.canvas,"set_overrideSorting",{"System.Boolean"},{&yes});r.call(v.canvas,"set_sortingLayerID",{"System.Int32"},{&sorting});
    v.tr=r.call(v.go,"get_transform");V2 rect{1024,300};r.call(v.tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&rect});
    v.graphic=addComponent(r,v.go,r.type("UnityEngine.UI","Text"));
    P label=r.get<P>(r.get<P>(progress,"scoreControl"),"comboText");P font=r.call(label,"get_font");r.call(v.graphic,"set_font",{"UnityEngine.Font"},{font});
    int fontSize=48,alignment=4,overflow=1;
    r.call(v.graphic,"set_fontSize",{"System.Int32"},{&fontSize});r.call(v.graphic,"set_alignment",{"UnityEngine.TextAnchor"},{&alignment});
    r.call(v.graphic,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&overflow});r.call(v.graphic,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&overflow});
    r.call(v.graphic,"set_raycastTarget",{"System.Boolean"},{&no});
   }else{
    v.graphic=addComponent(r,v.go,r.type("UnityEngine","SpriteRenderer"));r.call(v.graphic,"set_sprite",{"UnityEngine.Sprite"},{sprite});
    r.call(v.graphic,"set_sortingLayerID",{"System.Int32"},{&sorting});
    // Native judge-line materials may mask/replace the sampled texture.
    // Use a dedicated, shared Sprite material for full-color storyboard art.
    if(!storyMaterial){P shader=r.stat(r.type("UnityEngine","Shader"),"Find",{"System.String"},{r.string_new("Sprites/Default")});
     if(!r.alive(shader))throw std::runtime_error("Sprites/Default shader unavailable");
     P material=r.object_new(r.type("UnityEngine","Material"));keep(r,material);r.call(material,".ctor",{"UnityEngine.Shader"},{shader});storyMaterial=material;
    }
    r.invokeOn(r.resolve(r.type("UnityEngine","Renderer"),"SetMaterial",{"UnityEngine.Material"}),v.graphic,{storyMaterial});
   }
   // Independent root: do not inherit the native long/thin line scale or
   // alter the coordinate system used by its child notes.
   found=storyVisuals.emplace(index,v).first;
   log([NSString stringWithFormat:@"Storyboard line %d ready: %@",index,hasText?@"text":texture]);
  }catch(const std::exception&e){try{if(r.alive(createdRoot))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{createdRoot});}catch(...){}storyRetry[index]=clock+2;if(storyReported.insert(index).second)log([NSString stringWithFormat:@"Storyboard line %d (%@): %s",index,texture?:@"text",e.what()]);return;}
 }
 auto&v=found->second;
 if(!v.visible){bool yes=true;r.call(v.go,"SetActive",{"System.Boolean"},{&yes});v.visible=true;}
 P tr=r.call(line,"get_transform");float width=storyFrameWidth;
 struct Q{float x,y,z,w;};V3 pos=r.unbox<V3>(r.call(tr,"get_position"));Q rot=r.unbox<Q>(r.call(tr,"get_rotation"));
 r.call(v.tr,"set_position",{"UnityEngine.Vector3"},{&pos});r.call(v.tr,"set_rotation",{"UnityEngine.Quaternion"},{&rot});
 float factor=v.text?width*.04f/48.f:100.f*width/1350.f;
 V3 scale{factor*(float)trackValue(d[@"scaleXEvents"],now,1),factor*(float)trackValue(d[@"scaleYEvents"],now,1),1};
 r.call(v.tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});
 if(v.text){
  NSDictionary*event=eventAt(d[@"textEvents"],now);
  NSString*value=@"";
  if(event){NSString*a=[event[@"start"] description]?:@"",*b=[event[@"end"] description]?:@"";value=a;
   if([a containsString:@"%P%"]||[b containsString:@"%P%"]){a=[a stringByReplacingOccurrencesOfString:@"%P%" withString:@""];b=[b stringByReplacingOccurrencesOfString:@"%P%" withString:@""];double q=std::clamp((now-scalar(event[@"startTime"]))/std::max(.001,scalar(event[@"endTime"])-scalar(event[@"startTime"])),0.,1.);value=[b substringToIndex:MIN(b.length,(NSUInteger)std::round(double(a.length)+(double(b.length)-double(a.length))*q))];}
  }
  if(![v.lastText isEqualToString:value]){r.text(v.graphic,value.UTF8String);v.lastText=value;}
 }
 r.call(v.graphic,"set_color",{"UnityEngine.Color"},{&color});
 r.call(v.text?v.canvas:v.graphic,"set_sortingOrder",{"System.Int32"},{&order});
 bool no=false;r.call(nativeRenderer,"set_enabled",{"System.Boolean"},{&no});
}

}
void judgeWithHudPause(Runtime&r,P judge,P mi,void(*original)(P,P)){
 // attachUI animates the icon only. Keep the native top-left double-tap
 // region, including when the animated icon is hidden or scaled to zero.
 (void)r;original(judge,mi);
}
namespace {
const char*sourceControlList(int type){return type==1?"clickControls":type==2?"dragControls":type==3?"holdControls":"flickControls";}
P findSourceController(Runtime&r,P manager,P note){P controls=r.get<P>(manager,sourceControlList(r.get<int>(note,"type")));for(int i=0,n=r.count(controls);i<n;++i){P c=r.at(controls,i);if(r.get<P>(c,"noteInfor")==note&&r.alive(c))return c;}return nullptr;}
}
bool hasNoteController(Runtime&r,P line,int index,bool above){
 if(!currentChart)return false;P notes=r.get<P>(line,above?"notesAbove":"notesBelow");if(index<0||index>=r.count(notes))return false;
 P note=r.at(notes,index);if(!recoveredSourceNotes.count(note))return false;
 P progress=r.get<P>(line,"progressControl"),judge=r.get<P>(progress,"judgeControl"),manager=r.get<P>(judge,"noteUpdateManager");
 return findSourceController(r,manager,note)!=nullptr;
}
void recoverSourceNotes(Runtime&r,P manager){
 if(!currentChart)return;P progress=r.get<P>(manager,"progressControl"),judge=r.get<P>(manager,"judgeControl"),info=r.get<P>(manager,"levelInformation");
 if(!r.get<bool>(info,"chartLoaded"))return;
 float now=r.get<float>(progress,"nowTime"),world=r.staticValue<float>(r.klass("LevelInformation"),"Speed","System.Single");
 std::map<P,P>existing;
 for(const char*field:{"clickControls","dragControls","holdControls","flickControls"}){P list=r.get<P>(manager,field);for(int i=0,n=r.count(list);i<n;++i){P c=r.at(list,i);if(r.alive(c))existing[r.get<P>(c,"noteInfor")]=c;}}
 P notes=r.get<P>(judge,"chartNoteSortByTime"),lines=r.get<P>(judge,"judgeLineControls");int n=r.count(notes),lo=0,hi=n;
 while(lo<hi){int mid=(lo+hi)/2;if(r.get<float>(r.at(notes,mid),"realTime")<now-.25f)lo=mid+1;else hi=mid;}
 for(int i=lo;i<n;++i){P note=r.at(notes,i);float start=r.get<float>(note,"realTime");if(start>now+8)break;
  auto extra=extras.find(note);if(extra==extras.end()||!extra->second[@"pmRawSpeed"])continue;
  if(start-now>scalar(extra->second[@"pmVisible"],999999))continue;
  int li=r.get<int>(note,"judgeLineIndex")/2;if(li<0||li>=r.count(lines))continue;P line=r.at(lines,li);
  double current=sourceFloor(li,now,floor(r,info,li)),delta=scalar(extra->second[@"floorPosition"])-current;
  if(std::fabs(delta*scalar(extra->second[@"pmRawSpeed"],1)*world)>30)continue;
  auto present=existing.find(note);P controlObject=present==existing.end()?nullptr:present->second;
  if(!controlObject&&!r.get<bool>(note,"isJudged")&&start>=now-.001f){
   bool above=(r.get<int>(note,"judgeLineIndex")%2)==0;int index=r.get<int>(note,"noteIndex");P side=r.get<P>(line,above?"notesAbove":"notesBelow");
   if(index<0||index>=r.count(side)||r.at(side,index)!=note)continue;
   r.call(line,"CreateNote",{"System.Int32","System.Boolean"},{&index,&above});controlObject=findSourceController(r,manager,note);
   if(controlObject){recoveredSourceNotes.insert(note);r.call(controlObject,"Start");}
  }
  if(controlObject&&!r.get<bool>(controlObject,"isVisible")){
   // Correct a native floor/visibility gate only while the source geometry is near.
   r.put(controlObject,"isVisible",true);r.call(controlObject,"NoteMove");
  }
 }
}
void visuals(Runtime&r,P progress){
 storyFrameCamera=nullptr;storyFrameWidth=0;
 if(!currentChart)return;
 static double skewCleanupAt=0;double skewNow=NSDate.timeIntervalSinceReferenceDate;
 if(skewNow-skewCleanupAt>1){skewCleanupAt=skewNow;for(auto it=skewMeshes.begin();it!=skewMeshes.end();){if(!r.alive(target(r,it->second.renderer))){releaseSkew(r,it->second);it=skewMeshes.erase(it);}else ++it;}}
 if(!currentChart)return;P judge=r.get<P>(progress,"judgeControl"),lineList=r.get<P>(judge,"judgeLineControls"),info=r.get<P>(progress,"levelInformation");float now=r.get<float>(progress,"nowTime");NSArray*data=currentChart[@"judgeLineList"];int total=std::min<int>(r.count(lineList),(int)data.count);
 // Android also retires the stock cut-in line for RPE charts once playback is
 // prepared. It is not one of the chart's judgeLineControls and can otherwise
 // remain as an unrelated horizontal line at the center of the screen.
 if([currentChart[@"pmFormat"]isEqualToString:@"RPE"]&&now>=0&&r.get<bool>(progress,"_playPrepared")){
  P intro=r.get<P>(info,"judgeLineOfCutIn");
  if(r.alive(intro)){if(r.unbox<bool>(r.call(intro,"get_activeSelf"))){bool no=false;r.call(intro,"SetActive",{"System.Boolean"},{&no});}if(!rpeIntroRetired){rpeIntroRetired=true;log(@"Content RPE intro judge line retired after playback start");}}
 }
 if(total<=0)return;
 for(int i=0;i<total;++i){
  P line=r.at(lineList,i),renderer=r.get<P>(line,"_judgeLineSpriteRenderer");if(!r.alive(renderer))continue;
  // attachUI lines carry HUD animation data, not a drawable line/texture.
  // Keep the controller, transforms and indices; suppress only its visual.
  if(uiControlLines.count(i)){
   auto binding=std::find_if(hudLines.begin(),hudLines.end(),[&](const auto&entry){return entry.second==i;});
   if(binding!=hudLines.end()&&now>=0){try{updateHud(r,binding->first,line,data[i],now);}catch(const std::exception&e){if(hudErrors.insert(binding->first).second)log([NSString stringWithFormat:@"RPE HUD %d failed: %s",binding->first,e.what()]);}}
   bool no=false;if(r.unbox<bool>(r.call(renderer,"get_enabled")))r.call(renderer,"set_enabled",{"System.Boolean"},{&no});
   auto visual=storyVisuals.find(i);if(visual!=storyVisuals.end()&&visual->second.visible){r.call(visual->second.go,"SetActive",{"System.Boolean"},{&no});visual->second.visible=false;}
   continue;
  }
  if(inertLineVisuals.count(i)){if(r.unbox<bool>(r.call(renderer,"get_enabled"))){bool no=false;r.call(renderer,"set_enabled",{"System.Boolean"},{&no});}continue;}
  P tr=r.call(line,"get_transform");NSDictionary*d=data[i][@"pmDecor"];if(!d)continue;
  // Extended line scale is visual-only; never scale the note/controller parent.
  NSString*textureName=[d[@"Texture"] isKindOfClass:NSString.class]?d[@"Texture"]:nil;
  bool story=[d[@"textEvents"] count]>0||(textureName.length&&![textureName isEqualToString:@"line.png"]);
  Color color=story?Color{1,1,1,1}:r.unbox<Color>(r.call(renderer,"get_color"));
  if(!story&&[currentChart[@"pmFormat"]isEqualToString:@"RPE"]){
   float alpha=sourceLineAlpha(data[i][@"judgeLineDisappearEvents"],now,scalar(data[i][@"bpm"],120));
   if(alpha<=0&&color.a>.001f&&reportedLineAlphaCorrections.size()<12&&reportedLineAlphaCorrections.insert(i).second)
    log([NSString stringWithFormat:@"Content line alpha corrected after native update: line=%d native=%.3f source=%.3f time=%.3f",i,color.a,alpha,now]);
   color.a=alpha;
   bool visible=alpha>0;if(r.unbox<bool>(r.call(renderer,"get_enabled"))!=visible)r.call(renderer,"set_enabled",{"System.Boolean"},{&visible});
  }
  NSArray*colors=d[@"colorEvents"];if(colors.count){color.r=trackValue(colors,now,1,0);color.g=trackValue(colors,now,1,1);color.b=trackValue(colors,now,1,2);}
  int order=i<(int)storyOrders.size()?storyOrders[i]:3+i*2;
  r.call(renderer,"set_sortingOrder",{"System.Int32"},{&order});
  r.call(renderer,"set_color",{"UnityEngine.Color"},{&color});
  if(!story&&([d[@"scaleXEvents"]count]||[d[@"scaleYEvents"]count])){
   P display=nullptr;auto existing=plainLineRenderers.find(i);
   if(existing!=plainLineRenderers.end())display=existing->second;
   if(!r.alive(display)){
    P sprite=r.call(renderer,"get_sprite");if(!r.alive(sprite))continue;
    P go=r.object_new(r.type("UnityEngine","GameObject"));uint32_t handle=r.gchandle_new(go,false);
    try{
     r.call(go,".ctor",{"System.String"},{r.string_new("PhiMod Line Visual")});
     int layer=r.unbox<int>(r.call(r.call(line,"get_gameObject"),"get_layer"));r.call(go,"set_layer",{"System.Int32"},{&layer});
     P child=r.call(go,"get_transform"),sourceTransform=r.call(renderer,"get_transform");bool world=false;
     // Inherit the actual renderer's authored transform, not the note controller.
     r.call(child,"SetParent",{"UnityEngine.Transform","System.Boolean"},{sourceTransform,&world});
     V3 zero{0,0,0};r.call(child,"set_localPosition",{"UnityEngine.Vector3"},{&zero});r.call(child,"set_localEulerAngles",{"UnityEngine.Vector3"},{&zero});
     display=addComponent(r,go,r.type("UnityEngine","SpriteRenderer"));
     P material=r.call(renderer,"get_sharedMaterial");if(r.alive(material))r.call(display,"SetMaterial",{"UnityEngine.Material"},{material});
     visualRoots.push_back(handle);plainLineRenderers[i]=display;
    }catch(...){if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(handle);throw;}
   }
   P child=r.call(display,"get_transform");V3 scale{(float)trackValue(d[@"scaleXEvents"],now,1),(float)trackValue(d[@"scaleYEvents"],now,1),1};
   r.call(child,"set_localScale",{"UnityEngine.Vector3"},{&scale});
   P sourceSprite=r.call(renderer,"get_sprite");if(r.call(display,"get_sprite")!=sourceSprite)r.call(display,"set_sprite",{"UnityEngine.Sprite"},{sourceSprite});
   // A fresh renderer defaults to Simple; stock lines can use stretched/tiled
   // size independently of Sprite pixel bounds. Preserve that baseline on both axes.
   int drawMode=r.unbox<int>(r.call(renderer,"get_drawMode"));
   if(r.unbox<int>(r.call(display,"get_drawMode"))!=drawMode)r.call(display,"set_drawMode",{"UnityEngine.SpriteDrawMode"},{&drawMode});
   V2 sourceSize=r.unbox<V2>(r.call(renderer,"get_size")),displaySize=r.unbox<V2>(r.call(display,"get_size"));
   if(sourceSize.x!=displaySize.x||sourceSize.y!=displaySize.y)r.call(display,"set_size",{"UnityEngine.Vector2"},{&sourceSize});
   bool flipX=r.unbox<bool>(r.call(renderer,"get_flipX")),flipY=r.unbox<bool>(r.call(renderer,"get_flipY"));
   if(r.unbox<bool>(r.call(display,"get_flipX"))!=flipX)r.call(display,"set_flipX",{"System.Boolean"},{&flipX});
   if(r.unbox<bool>(r.call(display,"get_flipY"))!=flipY)r.call(display,"set_flipY",{"System.Boolean"},{&flipY});
   int layer=r.unbox<int>(r.call(renderer,"get_sortingLayerID"));r.call(display,"set_sortingLayerID",{"System.Int32"},{&layer});r.call(display,"set_sortingOrder",{"System.Int32"},{&order});r.call(display,"set_color",{"UnityEngine.Color"},{&color});
   bool visible=color.a>0;r.call(display,"set_enabled",{"System.Boolean"},{&visible});bool no=false;r.call(renderer,"set_enabled",{"System.Boolean"},{&no});
  }else{
  updateStory(r,i,line,renderer,d,data[i][@"judgeLineDisappearEvents"],scalar(data[i][@"bpm"],120),now,progress,color,order);
  }
 }
 // Fake notes are independent SpriteRenderers: never native score/judgement
 // controllers. Only the local 8-second window is allocated.
 if(!fakeScheduleReady){
  for(NSUInteger li=0;li<data.count;++li)for(NSString*side in @[@"notesAbove",@"notesBelow"])for(NSDictionary*n in data[li][side])if([n[@"pmFake"] boolValue]){
   double start=scalar(n[@"pmTime"],scalar(n[@"time"])/64);
   double end=start+((int)scalar(n[@"type"])==3?scalar(n[@"pmDuration"]):0);
   NSDictionary*decor=data[li][@"pmDecor"];bool cover=decor[@"isCover"]?[decor[@"isCover"]boolValue]:true;
   if((int)scalar(n[@"type"])!=3&&!cover)end=std::numeric_limits<double>::infinity();
   fakeSchedule.push_back(fakeNotes.size());fakeNotes.push_back({n,(int)li,[side isEqualToString:@"notesBelow"],start,end});
  }
  std::stable_sort(fakeSchedule.begin(),fakeSchedule.end(),[](size_t a,size_t b){return fakeNotes[a].start<fakeNotes[b].start;});
  fakeScheduleReady=true;
 }
 auto hideFake=[&](size_t i){
  auto visual=fakeVisualCache.find(i);if(visual==fakeVisualCache.end()||!visual->second.shown)return;
  bool no=false;P renderer=target(r,fakeRenderers.at(i));r.call(renderer,"set_enabled",{"System.Boolean"},{&no});visual->second.shown=false;
  auto ends=fakeHoldEnds.find(i);if(ends!=fakeHoldEnds.end())for(int k=0;k<2;++k)if(visual->second.capShown[k]){
   P sr=target(r,k?ends->second.second:ends->second.first);r.call(sr,"set_enabled",{"System.Boolean"},{&no});visual->second.capShown[k]=false;
  }
 };
 // A practice seek/repeat rebuilds the window once; normal frames visit only
 // notes whose existing eight-second visibility window has begun.
 if(now<fakeLastTime){for(size_t i:activeFakes)hideFake(i);activeFakes.clear();fakeCursor=0;}
 fakeLastTime=now;
 while(fakeCursor<fakeSchedule.size()&&fakeNotes[fakeSchedule[fakeCursor]].start-8<=now){size_t i=fakeSchedule[fakeCursor++];if(now<fakeNotes[i].end)activeFakes.insert(i);}
 for(auto it=activeFakes.begin();it!=activeFakes.end();){if(now>=fakeNotes[*it].end){hideFake(*it);it=activeFakes.erase(it);}else ++it;}
 if(activeFakes.empty())return;
 float worldSpeed=r.staticValue<float>(r.klass("LevelInformation"),"Speed","System.Single");
 double retryClock=NSDate.timeIntervalSinceReferenceDate;
 std::map<int,double>frameFloors;std::map<int,P>frameLines;
 for(size_t i:activeFakes){
 auto retry=fakeRetryAt.find(i);if(retry!=fakeRetryAt.end()&&retryClock<retry->second)continue;
 auto&f=fakeNotes[i];double start=f.start;
 if(f.line>=total)continue;
 auto renderEntry=fakeRenderers.find(i);P renderer=renderEntry==fakeRenderers.end()?nullptr:target(r,renderEntry->second);
 auto lineEntry=frameLines.find(f.line);if(lineEntry==frameLines.end())lineEntry=frameLines.emplace(f.line,r.at(lineList,f.line)).first;P line=lineEntry->second;
 if(!renderer){
  P go=nullptr;std::vector<P>created;std::vector<uint32_t>newHandles;
  try{
   int type=(int)scalar(f.note[@"type"],1);
   const char*prefabName=type==2?"Drag":type==4?"Flick":type==3?"Hold":"Click";
   const char*controlName=type==2?"DragControl":type==4?"FlickControl":type==3?"HoldControl":"ClickControl";
   P prefab=r.get<P>(line,prefabName);
   if(!r.alive(prefab))throw std::runtime_error("Native note prefab is not ready");
   P controller=r.component(prefab,r.klass(controlName));
   if(!r.alive(controller))throw std::runtime_error("Native prefab controller missing");
   P sprites[3]{};
   if(type==3){
    P images=r.get<P>(controller,"noteImages");
    if(!images||r.array_length(images)<3)throw std::runtime_error("Hold prefab noteImages incomplete");
    sprites[0]=r.arrayAt(images,1);sprites[1]=r.arrayAt(images,0);sprites[2]=r.arrayAt(images,2);
   }else sprites[0]=r.get<P>(controller,"noteImage");
   for(int k=0;k<(type==3?3:1);++k)if(!r.alive(sprites[k]))throw std::runtime_error("Native serialized note sprite is not ready");
   for(int k=0;k<(type==3?3:1);++k)sprites[k]=pmfeatures::noteSprite(r,type,k==0?1:k==1?0:2,sprites[k]);
   // CreateNote uses the prefab's actual scale, the user's noteScale and
   // Screen aspect compensation. A fixed .22 cannot reproduce that size.
   P parent=r.call(line,"get_transform"),prefabTransform=r.call(prefab,"get_transform");
   V3 prefabScale=r.unbox<V3>(r.call(prefabTransform,"get_lossyScale"));
   V3 parentScale=r.unbox<V3>(r.call(parent,"get_lossyScale"));
   float noteScale=r.get<float>(line,"noteScale");
   int screenWidth=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_width"));
   int screenHeight=r.unbox<int>(r.stat(r.type("UnityEngine","Screen"),"get_height"));
   if(screenHeight<=0||screenWidth<=0||!std::isfinite(noteScale)||noteScale<=0)throw std::runtime_error("Native note sizing not ready");
   // The line may currently be hidden by an animated zero scale. Retry after
   // it becomes visible rather than caching an infinite local scale forever.
   for(float v:{parentScale.x,parentScale.y,parentScale.z})if(!std::isfinite(v)||std::fabs(v)<1e-6f)throw std::runtime_error("Fake note parent temporarily has zero scale");
   float factor=noteScale*std::min(1.f,(float(screenWidth)/screenHeight)/(16.f/9.f));
   V3 base{prefabScale.x/parentScale.x*factor,prefabScale.y/parentScale.y*factor,prefabScale.z/parentScale.z*factor};
   P sourceRenderer=r.component(prefab,r.type("UnityEngine","SpriteRenderer"));
   int layer=r.unbox<int>(r.call(prefab,"get_layer"));
   int sortingLayer=sourceRenderer?r.unbox<int>(r.call(sourceRenderer,"get_sortingLayerID")):0;
   int order=type==3?storyHoldOrder:storyNoteOrder;
   auto makeRenderer=[&](P sprite,P owner,const char*name){
    P obj=r.object_new(r.type("UnityEngine","GameObject"));keep(r,obj);created.push_back(obj);
    r.call(obj,".ctor",{"System.String"},{r.string_new(name)});
    r.call(obj,"set_layer",{"System.Int32"},{&layer});
    P transform=r.call(obj,"get_transform");bool no=false;
    r.call(transform,"SetParent",{"UnityEngine.Transform","System.Boolean"},{owner,&no});
    P sr=addComponent(r,obj,r.type("UnityEngine","SpriteRenderer"));
    r.call(sr,"set_sprite",{"UnityEngine.Sprite"},{sprite});
    r.call(sr,"set_enabled",{"System.Boolean"},{&no});
    r.call(sr,"set_sortingLayerID",{"System.Int32"},{&sortingLayer});
    r.call(sr,"set_sortingOrder",{"System.Int32"},{&order});
    if(r.alive(sourceRenderer)){P material=r.call(sourceRenderer,"get_sharedMaterial");if(material)r.invokeOn(r.resolve(r.type("UnityEngine","Renderer"),"SetMaterial",{"UnityEngine.Material"}),sr,{material});}
    return sr;
   };
   renderer=makeRenderer(sprites[0],parent,"PhiMod RPE Fake");go=created.front();
   P tr=r.call(renderer,"get_transform");
   if(type!=3&&f.below){V3 angles{180,0,0};r.call(tr,"set_localEulerAngles",{"UnityEngine.Vector3"},{&angles});}
   uint32_t head=0,tail=0;
   if(type==3){
    P headRenderer=makeRenderer(sprites[1],tr,"PhiMod Fake Hold Head");
    P tailRenderer=makeRenderer(sprites[2],tr,"PhiMod Fake Hold Tail");
    head=r.gchandle_new(headRenderer,false);newHandles.push_back(head);
    tail=r.gchandle_new(tailRenderer,false);newHandles.push_back(tail);
   }
   uint32_t body=r.gchandle_new(renderer,false);newHandles.push_back(body);
   FakeVisualCache cached;cached.transform=tr;
   if(type==3){cached.bounds=r.unbox<Bounds>(r.call(sprites[0],"get_bounds"));cached.capTransforms[0]=r.call(target(r,head),"get_transform");cached.capTransforms[1]=r.call(target(r,tail),"get_transform");
    for(int k=0;k<2;++k){V3 cp{0,cached.bounds.center.y+(k?cached.bounds.extents.y:-cached.bounds.extents.y),0};r.call(cached.capTransforms[k],"set_localPosition",{"UnityEngine.Vector3"},{&cp});}
   }
   fakeVisualCache[i]=cached;
   fakeScales[i]=base;if(type==3)fakeHoldEnds[i]={head,tail};fakeRenderers[i]=body;
   bool report=i<8||failedFakes.count(i);fakeRetryAt.erase(i);failedFakes.erase(i);
   if(report)log([NSString stringWithFormat:@"Fake note %zu ready type=%d scale=(%.5f,%.5f) nativeFactor=%.5f",i,type,base.x,base.y,factor]);
  }catch(const std::exception&e){
   for(auto h:newHandles)r.gchandle_free(h);
   for(P obj:created)try{if(r.alive(obj))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{obj});}catch(...){}
   renderer=nullptr;fakeRetryAt[i]=NSDate.timeIntervalSinceReferenceDate+.5;
   if(failedFakes.insert(i).second)log([NSString stringWithFormat:@"Fake note %zu deferred (will retry): %s",i,e.what()]);
   continue;
  }
 }

 auto floorEntry=frameFloors.find(f.line);
 if(floorEntry==frameFloors.end()){
  // Avoid managed array reads when the source speed track is available.
  auto source=sourceFloors.find(f.line);double value;
  if(source!=sourceFloors.end()&&!source->second.empty())value=phimod::rpeFloor(source->second,now,0);
  else{int lineIndex=r.get<int>(line,"index");value=floor(r,info,lineIndex);}
  floorEntry=frameFloors.emplace(f.line,value).first;
 }
 double currentFloor=floorEntry->second;
 auto&visual=fakeVisualCache.at(i);
 bool isHold=(int)scalar(f.note[@"type"])==3;
 NSDictionary*decor=data[f.line][@"pmDecor"];
 double distance=(scalar(f.note[@"floorPosition"])-currentFloor)*rpeFloorToDistance+scalar(f.note[@"pmYOffset"]);
 auto geometry=rpeGeometry(scalar(f.note[@"floorPosition"])-currentFloor,scalar(f.note[@"pmEndFloor"],scalar(f.note[@"floorPosition"]))-currentFloor,0,scalar(f.note[@"pmRawSpeed"],1),scalar(f.note[@"pmYOffset"]),control(decor,@"yControl",distance),worldSpeed,isHold&&now>=start);
 V3 position{rpeHorizontalPosition(scalar(f.note[@"positionX"]),isHold,control(decor,@"posControl",distance),trackValue(decor[@"inclineEvents"],now,0),geometry.head,isHold?0:notePerspectiveWidth(r,decor,now)),f.below?-geometry.head:geometry.head,0};
 P tr=visual.transform;
 float sizeX=scalar(f.note[@"pmSize"],1)*control(decor,@"sizeControl",distance);
 if(!std::isfinite(sizeX))sizeX=1;
 // Preserve native prefab aspect; RPE size changes only note width.
 V3 size=fakeScales.at(i);size.x*=sizeX;
 if(isHold){
  const Bounds&bounds=visual.bounds;
  if(bounds.extents.y>0.00001f){
   auto layout=rpeHoldLayout(geometry,bounds.extents.y*2,bounds.center.y-bounds.extents.y,f.below);
   size.y=layout.scale;position.y=layout.origin;
   auto ends=fakeHoldEnds.find(i);
   if(ends!=fakeHoldEnds.end())for(int k=0;k<2;++k){P sr=target(r,k?ends->second.second:ends->second.first);if(!sr)continue;
    if(!visual.scaleSet||visual.scale.y!=size.y){P ct=visual.capTransforms[k];V3 cs{1,.22f/std::fabs(size.y),1};r.call(ct,"set_localScale",{"UnityEngine.Vector3"},{&cs});}
   }
  }
 }
 r.call(tr,"set_localPosition",{"UnityEngine.Vector3"},{&position});
 if(!visual.scaleSet||visual.scale.x!=size.x||visual.scale.y!=size.y||visual.scale.z!=size.z){r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&size});visual.scale=size;visual.scaleSet=true;}
 float alpha=scalar(f.note[@"pmAlpha"],1);
 if(!std::isfinite(alpha)||alpha<0)alpha=0;
 if(alpha>1)alpha=1;
 alpha*=std::clamp((float)control(decor,@"alphaControl",distance),0.f,1.f);
 if(start-now>scalar(f.note[@"pmVisible"],999999))alpha=0;
 bool cover=decor[@"isCover"]?[decor[@"isCover"]boolValue]:true;
 if(rpeCovered(cover,now,start,scalar(f.note[@"floorPosition"]),currentFloor,scalar(f.note[@"pmRawSpeed"],1)))alpha=0;
 if(!isHold)applySkew(r,renderer,rpeSkew(scalar(f.note[@"positionX"])*75,control(decor,@"skewControl",distance),f.below,size.x,size.y));
 Color color{1,1,1,alpha};
 bool colorChanged=!visual.colorSet||visual.color.a!=color.a;
 auto ends=fakeHoldEnds.find(i);if(ends!=fakeHoldEnds.end())for(int k=0;k<2;++k){
  P sr=target(r,k?ends->second.second:ends->second.first);bool show=k||now<start;
  if(colorChanged)r.call(sr,"set_color",{"UnityEngine.Color"},{&color});
  if(visual.capShown[k]!=show){r.call(sr,"set_enabled",{"System.Boolean"},{&show});visual.capShown[k]=show;}
 }
 if(colorChanged){r.call(renderer,"set_color",{"UnityEngine.Color"},{&color});visual.color=color;visual.colorSet=true;}
 if(!visual.shown){bool yes=true;r.call(renderer,"set_enabled",{"System.Boolean"},{&yes});visual.shown=true;}

}
}
// Prepare before native NoteMove instantiates Perfect/Good effects. Clones inherit
// renderer sorting, avoiding a global Instantiate hook or a per-frame scene scan.
void prepareHoldHitFX(Runtime&r,P controlObject){
 if(!currentChart)return;
 P body=r.get<P>(controlObject,"_holdSpriteRenderer");if(!r.alive(body))return;
 int layer=r.unbox<int>(r.call(body,"get_sortingLayerID"));
 int floor=std::max(storyNoteOrder,storyHoldOrder)+1;
 for(const char*field:{"perfect","good"}){
  P prefab=r.get<P>(controlObject,field);if(!prefab)continue;
  auto found=holdHitFX.find(prefab);
  if(found==holdHitFX.end()){
   if(!r.alive(prefab))continue;
   P renderers=r.children(prefab,r.type("UnityEngine","Renderer"));
   if(!renderers||!r.array_length(renderers))continue;
   auto&state=holdHitFX[prefab];
   for(uintptr_t i=0;i<r.array_length(renderers);++i){P renderer=r.arrayAt(renderers,int(i));
    int originalLayer=r.unbox<int>(r.call(renderer,"get_sortingLayerID")),originalOrder=r.unbox<int>(r.call(renderer,"get_sortingOrder"));
    state.renderers.push_back({r.gchandle_new(renderer,false),originalLayer,originalOrder});
   }
   found=holdHitFX.find(prefab);
  }
  auto&state=found->second;
  if(state.renderers.empty()||(state.appliedLayer==layer&&state.appliedFloor==floor))continue;
  int lowest=state.renderers.front().order;for(auto&saved:state.renderers)lowest=std::min(lowest,saved.order);
  int shift=std::max(0,floor-lowest);
  for(auto&saved:state.renderers){P renderer=r.gchandle_get_target(saved.root);int order=saved.order+shift;
   r.call(renderer,"set_sortingLayerID",{"System.Int32"},{&layer});r.call(renderer,"set_sortingOrder",{"System.Int32"},{&order});
  }
  state.appliedLayer=layer;state.appliedFloor=floor;
  log([NSString stringWithFormat:@"Hold hit FX sorting prepared: %s renderers=%lu floor=%d layer=%d",field,(unsigned long)state.renderers.size(),floor,layer]);
 }
}
void noteMoved(Runtime&r,P controlObject,bool hold){
 if(!r.alive(controlObject))return;
 P note=r.get<P>(controlObject,"noteInfor");auto it=extras.find(note);if(it==extras.end())return;
 NSDictionary*n=it->second;int index=r.get<int>(note,"judgeLineIndex")/2;NSArray*lines=currentChart[@"judgeLineList"];
 NSDictionary*d=index>=0&&index<(int)lines.count?lines[index][@"pmDecor"]:nil;
 P progress=r.get<P>(controlObject,"progressControl"),info=r.get<P>(controlObject,"levelInformation"),tr=r.call(controlObject,"get_transform");
 float now=r.get<float>(progress,"nowTime"),start=r.get<float>(note,"realTime");
 // Native NoteMove may hide/destroy a judged renderer in this same frame.
 // Never re-enable it from the RPE visual pass after judgement. Holds are
 // different: their head can be judged while the body remains drawable.
 bool controlJudged=r.get<bool>(controlObject,"isJudged");
 bool controlMissed=hold&&r.get<bool>(controlObject,"missed");
 // Do not use ChartNote.isJudged alone: preview/autoplay may reserve it
 // before the visible controller is actually finished. Preserve native miss fade.
 // judgeOver also means successful early-tail scoring (native end - 0.22s).
 // It is not a renderer lifetime flag. Let native missed Holds fade, and keep
 // successful bodies/skin geometry through the authored end time.
 bool ended=phimod::noteRenderFinished(r.get<int>(note,"type"),controlJudged,now,start,hold?r.get<float>(note,"holdTime"):0);
 if(ended){
  for(const char*field:hold?std::vector<const char*>{"_holdHeadSpriteRenderer","_holdSpriteRenderer","_holdEndSpriteRenderer1"}:std::vector<const char*>{"_spriteRenderer"}){P renderer=r.get<P>(controlObject,field);if(r.alive(renderer)){bool no=false;r.call(renderer,"set_enabled",{"System.Boolean"},{&no});}}
  return;
 }

 V3 scale=r.unbox<V3>(r.call(tr,"get_localScale"));if(!noteScales.count(controlObject))noteScales[controlObject]=scale;
 double currentFloor=sourceFloor(index,now,floor(r,info,index));
 float delta=scalar(n[@"floorPosition"])-currentFloor;
 float distance=delta*rpeFloorToDistance+scalar(n[@"pmYOffset"]);
 float yControlValue=control(d,@"yControl",distance);
 scale.x=noteScales[controlObject].x*scalar(n[@"pmSize"],1)*control(d,@"sizeControl",distance);
 r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});
 if(n[@"pmRawSpeed"]){
 float speed=r.staticValue<float>(r.klass("LevelInformation"),"Speed","System.Single");
 V3 position=r.unbox<V3>(r.call(tr,"get_localPosition"));
 bool below=r.get<int>(note,"judgeLineIndex")%2;
 float rawSpeed=scalar(n[@"pmRawSpeed"],1);
 float yControl=control(d,@"yControl",distance);
 float yOffset=scalar(n[@"pmYOffset"],0);
 position.x=r.get<float>(note,"positionX");
 if(hold){
  // Android applyRpeGeometry: both endpoints use the same source integral.
  // Once started, pin the head to the line and shorten the remaining body.
  auto geometry=rpeGeometry(delta,scalar(n[@"pmEndFloor"],scalar(n[@"floorPosition"]))-currentFloor,0,rawSpeed,yOffset,yControl,speed,now>=start);
  P body=r.get<P>(controlObject,"_holdSpriteRenderer"),sprite=r.alive(body)?r.call(body,"get_sprite"):nullptr;
  if(r.alive(sprite)){
   Bounds bounds=r.unbox<Bounds>(r.call(sprite,"get_bounds"));float height=2*bounds.extents.y;
   if(height>0.00001f){
    auto layout=rpeHoldLayout(geometry,height,bounds.center.y-bounds.extents.y,below);
    scale.y=layout.scale;position.y=layout.origin;
    // Native below Holds can already be rotated; mirror exactly once via scale.
    V3 zero{0,0,0};r.call(tr,"set_localEulerAngles",{"UnityEngine.Vector3"},{&zero});
    for(int k=0;k<2;++k){
     P child=r.get<P>(controlObject,k?"holdEnd":"holdHead");if(!r.alive(child))continue;
     P ct=r.call(child,"get_transform");V3 cs=r.unbox<V3>(r.call(ct,"get_localScale"));cs.y=std::fabs(scale.x)/std::max(.00001f,std::fabs(scale.y));
     r.call(ct,"set_localScale",{"UnityEngine.Vector3"},{&cs});
     if(k||!r.get<bool>(controlObject,"_holdHeadIsDestroyed")){V3 cp=r.unbox<V3>(r.call(ct,"get_localPosition"));cp.y=bounds.center.y+(k?bounds.extents.y:-bounds.extents.y);
      P cap=r.get<P>(controlObject,k?"_holdEndSpriteRenderer1":"_holdHeadSpriteRenderer");P capSprite=r.alive(cap)?r.call(cap,"get_sprite"):nullptr;
      if(r.alive(capSprite)){Bounds cb=r.unbox<Bounds>(r.call(capSprite,"get_bounds"));cp.y=rpeHoldCapPosition(cp.y,cb.center.y,cb.extents.y,cs.y,k!=0,false);}
      r.call(ct,"set_localPosition",{"UnityEngine.Vector3"},{&cp});}
    }
    r.call(tr,"set_localScale",{"UnityEngine.Vector3"},{&scale});
   }
  }
 }else{
  auto geometry=rpeGeometry(delta,scalar(n[@"pmEndFloor"],scalar(n[@"floorPosition"]))-currentFloor,0,rawSpeed,yOffset,yControl,speed,false);
  position.y=below?-geometry.head:geometry.head;
  position.x=rpeHorizontalPosition(position.x,false,control(d,@"posControl",distance),trackValue(d[@"inclineEvents"],now,0),geometry.head,notePerspectiveWidth(r,d,now));
 }
 position.z=0;
 r.call(tr,"set_localPosition",{"UnityEngine.Vector3"},{&position});
}
 float alpha=scalar(n[@"pmAlpha"],1)*control(d,@"alphaControl",distance);
 if(!std::isfinite(alpha)||alpha<0)alpha=0;if(alpha>1)alpha=1;
 if(start-now>scalar(n[@"pmVisible"],999999))alpha=0;
 if(hold&&std::fabs(yControlValue)<0.0001f)alpha=0;
 bool cover=d[@"isCover"]?[d[@"isCover"]boolValue]:true;
 if(n[@"pmRawSpeed"]&&rpeCovered(cover,now,start,scalar(n[@"floorPosition"]),currentFloor,scalar(n[@"pmRawSpeed"],1)))alpha=0;
 if(hold&&now>=start+r.get<float>(note,"holdTime"))alpha=0;
 for(const char*field:hold?std::vector<const char*>{"_holdHeadSpriteRenderer","_holdSpriteRenderer","_holdEndSpriteRenderer1"}:std::vector<const char*>{"_spriteRenderer"}){
  P renderer=r.get<P>(controlObject,field);if(!r.alive(renderer))continue;
  Color color=r.unbox<Color>(r.call(renderer,"get_color"));
  bool sourceGeometry=n[@"pmRawSpeed"]!=nil;
  // Android: native Hold fading/visibility is based on its constant-speed
  // geometry; do not let it flash a source-geometry Hold during its lifetime.
  color.a=(sourceGeometry&&!controlMissed)?alpha:std::min(color.a,alpha);
  if(sourceGeometry&&!controlMissed){
   bool show=alpha>0&&!(hold&&!strcmp(field,"_holdHeadSpriteRenderer")&&r.get<bool>(controlObject,"_holdHeadIsDestroyed"));
   // This branch is reached only while the control is alive and unjudged (or
   // while a Hold body is still active), so enabling here cannot resurrect a
   // Tap/Flick/Drag after its judgement.
   r.call(renderer,"set_enabled",{"System.Boolean"},{&show});
  }
  r.call(renderer,"set_color",{"UnityEngine.Color"},{&color});
  int order=hold?storyHoldOrder:storyNoteOrder;r.call(renderer,"set_sortingOrder",{"System.Int32"},{&order});
 }
}
void finishNoteGeometry(Runtime&r,P controlObject,bool hold){
 if(hold||!currentChart||!r.alive(controlObject))return;P note=r.get<P>(controlObject,"noteInfor");auto found=extras.find(note);if(found==extras.end())return;
 int index=r.get<int>(note,"judgeLineIndex")/2;NSArray*lines=currentChart[@"judgeLineList"];if(index<0||index>=(int)lines.count)return;
 NSDictionary*d=lines[index][@"pmDecor"];P renderer=r.get<P>(controlObject,"_spriteRenderer");
 if(![d[@"skewControl"]count]&&!skewMeshes.count(renderer))return;
 float now=r.get<float>(r.get<P>(controlObject,"progressControl"),"nowTime");double current=sourceFloor(index,now,0);
 double distance=(scalar(found->second[@"floorPosition"])-current)*rpeFloorToDistance+scalar(found->second[@"pmYOffset"]);
 V3 scale=r.unbox<V3>(r.call(r.call(controlObject,"get_transform"),"get_localScale"));
 applySkew(r,renderer,rpeSkew(scalar(found->second[@"positionX"])*75,control(d,@"skewControl",distance),r.get<int>(note,"judgeLineIndex")%2,scale.x,scale.y));
}
void ranking(Runtime&r,P self,P mi,void(*original)(P,P)){if(!baseline){original(self,mi);return;}P previous=r.get<P>(self,"song");uint32_t oldRoot=r.gchandle_new(previous,false);P official=decode(r,baseline,"SongBase");uint32_t newRoot=r.gchandle_new(official,false);try{r.put(self,"song",official);original(self,mi);r.put(self,"song",previous);}catch(...){try{r.put(self,"song",previous);}catch(...){}r.gchandle_free(oldRoot);r.gchandle_free(newRoot);throw;}r.gchandle_free(oldRoot);r.gchandle_free(newRoot);}
void validatePcmCopy(Runtime&r){
 float samples[]={.25f,-.5f,0.f,1.f};int zero=0,count=4;void*ptr=samples;
 P data=r.array_new(r.type("System","Single"),count);
 if(!data)throw std::runtime_error("PCM preflight allocation failed");
 uint32_t root=r.gchandle_new(data,false);
 try{
  r.stat(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",
      {"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,data,&count});
  for(int i=0;i<count;++i)if(r.unbox<float>(r.arrayAt(data,i))!=samples[i])
   throw std::runtime_error("PCM preflight readback mismatch");
 }catch(...){r.gchandle_free(root);throw;}
 r.gchandle_free(root);PMDiagnosticsWrite("Content PCM copy preflight passed (4 float elements)");
}
void validate(Runtime&r){
 validateHud(r);
 r.resolve(r.type("UnityEngine","Sprite"),"OverrideGeometry",{"UnityEngine.Vector2[]","System.UInt16[]"});
 r.resolve(r.type("UnityEngine","Sprite"),"get_vertices");r.resolve(r.type("UnityEngine","Sprite"),"get_triangles");
 r.field(r.klass("ChapterSelector"),"_chapterInfos","ChapterInfo[]",false);
 r.field(r.klass("ChapterSelector"),"chapterPanel","UnityEngine.RectTransform",false);
 r.field(r.klass("ChapterInfo"),"chapterCode","System.String",false);
 r.field(r.klass("ChapterInfo"),"coverAssetCode","System.String",false);
 r.field(r.klass("ChapterInfo"),"coverBlurAssetCode","System.String",false);
 r.field(r.klass("ChapterInfo"),"play","UnityEngine.UI.Button",false);
 r.field(r.klass("ChapterInfo"),"locked","UnityEngine.GameObject",false);
 r.field(r.klass("ChapterInfo"),"songInfo","ChapterSongInfo",false);
 r.field(r.klass("ChapterInfo"),"title","UnityEngine.UI.Text",false);
 r.field(r.klass("ChapterInfo"),"subTitle","UnityEngine.UI.Text",false);
 P texture=r.type("UnityEngine","Texture2D");r.resolve(texture,".ctor",{"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"});r.resolve(texture,"get_width");r.resolve(texture,"get_height");
 r.resolve(r.type("UnityEngine","ImageConversion"),"LoadImage",{"UnityEngine.Texture2D","System.Byte[]","System.Boolean"},true);
 P lowPreview=r.klass("AddressableImageLoaderWithLowResPreview");r.field(r.klass("AddressableImageLoader"),"_initialized","System.Int32",false);r.resolve(lowPreview,"CheckInitialized");r.resolve(lowPreview,"SetLowResImage",{"System.String"});r.resolve(lowPreview,"SetImageWithTransition",{"System.String","System.Single"});r.resolve(lowPreview,"get_Code");r.resolve(lowPreview,"set_Code",{"System.String"});r.field(lowPreview,"loadedImage","System.Boolean",false);
 r.resolve(r.type("UnityEngine","Transform"),"SetSiblingIndex",{"System.Int32"});
 P probe=r.object_new(r.klass("Chapter"));
 if(!probe)throw std::runtime_error("Reference preflight allocation failed");
 uint32_t probeRoot=r.gchandle_new(probe,false);
 try{
  P text=r.string_new("PhiMod reference probe");
  r.put(probe,"chapterCode",text);
  if(r.get<P>(probe,"chapterCode")!=text)throw std::runtime_error("Reference preflight mismatch");
  r.put<P>(probe,"chapterCode",nullptr);
 }catch(...){r.gchandle_free(probeRoot);throw;}
 r.gchandle_free(probeRoot);log(@"Content reference write preflight passed");
 r.resolve(r.klass("SongsItem"),"GetLevelStartInfo",{"System.Int32"});r.resolve(r.klass("SongSelectorItem"),"GetLevelStartInfo",{"System.Int32"});
 r.resolve(r.klass("SongSelector"),"get_SongItems");r.resolve(r.klass("SongSelector"),"SetLevel",{"System.Int32"});r.resolve(r.klass("SongSelector"),"NormalStart");
 r.field(r.klass("SongSelector"),"nowSong","System.Int32",false);r.field(r.klass("SongSelector"),"nowLevel","System.Int32",false);r.field(r.klass("SongSelector"),"exit","System.Boolean",false);r.field(r.klass("SongSelector"),"isMoving","System.Boolean",false);
 r.field(r.klass("GameInformation"),"nowChapterCode","System.String",true);r.field(r.klass("GameInformation"),"nextScene","System.String",true);r.field(r.klass("GameInformation"),"song","SongBase",false);r.field(r.klass("GameInformation"),"chapters","Chapter[]",false);
 r.field(r.klass("ChartNote"),"judgeLineIndex","System.Int32",false);r.field(r.klass("LevelControl"),"chart","Chart",false);r.field(r.klass("LevelControl"),"songsName","UnityEngine.UI.Text",false);
 r.field(r.klass("LevelInformation"),"floorPositions","System.Single[]",false);r.field(r.klass("LevelInformation"),"Speed","System.Single",true);
 P renderer=r.type("UnityEngine","SpriteRenderer");r.resolve(renderer,"get_sprite");r.resolve(renderer,"set_sprite",{"UnityEngine.Sprite"});r.resolve(renderer,"get_color");r.resolve(renderer,"set_color",{"UnityEngine.Color"});r.resolve(renderer,"set_sortingOrder",{"System.Int32"});r.resolve(renderer,"get_sortingOrder");r.resolve(r.type("UnityEngine","Sprite"),"Create",{"UnityEngine.Texture2D","UnityEngine.Rect","UnityEngine.Vector2","System.Single"},true);
 r.resolve(texture,".ctor",{"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"});
 P uiImage=r.type("UnityEngine.UI","Image");r.resolve(uiImage,"get_sprite");r.resolve(uiImage,"set_sprite",{"UnityEngine.Sprite"});r.field(r.klass("AddressableImageLoader"),"_image","UnityEngine.UI.Image",false);r.field(r.klass("AddressableImageLoader"),"_sprite","UnityEngine.SpriteRenderer",false);
 r.resolve(r.type("UnityEngine","TextAsset"),".ctor",{"System.String"});r.resolve(r.type("UnityEngine","AudioClip"),"Create",{"System.String","System.Int32","System.Int32","System.Int32","System.Boolean"},true);r.resolve(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",{"System.IntPtr","System.Int32","System.Array","System.Int32"},true);
 r.resolve(r.type("UnityEngine","AudioClip"),"SetData",{"System.Single[]","System.Int32"});
 // Fake note rendering needs these; missing fields fall through to fallback
 // chains inside visuals() rather than aborting the frame.
 for(const char*name:{"Click","Drag","Flick","Hold"})
  try{r.field(r.klass("JudgeLineControl"),name,"UnityEngine.GameObject",false);}catch(...){}
 for(const char*name:{"clickControls","dragControls","holdControls","flickControls"}){
  std::string t="System.Collections.Generic.List<";t+=!strcmp(name,"clickControls")?"ClickControl":!strcmp(name,"dragControls")?"DragControl":!strcmp(name,"holdControls")?"HoldControl":"FlickControl";t+='>';
  try{r.field(r.klass("NoteUpdateManager"),name,t.c_str(),false);}catch(...){}
 }
 validatePcmCopy(r);
}
}