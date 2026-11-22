#include <memory>
// Included once after the selector's checkedSong implementation, at global scope.
namespace pmnativeosrows {
using pmbridge::P;
using pmbridge::Runtime;
namespace {
struct Root {
    Runtime &r;
    uint32_t handle;
    Root(Runtime &rt,P obj):r(rt),handle(obj?rt.gchandle_new(obj,false):0){
        if(!handle)throw std::runtime_error("Native detail snapshot allocation failed");
    }
    ~Root(){r.gchandle_free(handle);}
    Root(const Root&)=delete;
    P get()const{return r.gchandle_get_target(handle);}
};
using Key=std::pair<std::string,std::string>;
Key key(NSString *idValue,NSString *difficulty){
    return {idValue.UTF8String?:"",difficulty.UTF8String?:""};
}
struct Cover {
    NSData *bytes=nil;
    // Only a plain WeakReference crosses lookups. The donor's Image owns the
    // displayed sprite. Recreate it from immutable bytes if Unity unloads it.
    std::unique_ptr<Root> weak;
};
struct Saved {
    Root row;
    int slot;
    std::shared_ptr<Cover> cover;
    Saved(Runtime &r,P data,int level,std::shared_ptr<Cover> art):row(r,data),slot(level),cover(std::move(art)){}
};
struct Batch {
    Runtime &r;
    std::map<Key,std::unique_ptr<Saved>> rows;
    std::map<std::string,std::shared_ptr<Cover>> covers;
    const NSUInteger revision;
    explicit Batch(Runtime &rt):r(rt),revision(PMContentStore.shared.revision){}
};
std::unique_ptr<Batch> batch;

void destroy(Runtime &r,P object){if(r.alive(object))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{object});}
P sprite(Runtime &r,Cover &cover){
    if(cover.weak){P cached=r.call(cover.weak->get(),"get_Target");if(r.alive(cached))return cached;}
    int length=int(cover.bytes.length),zero=0;void *ptr=(void*)cover.bytes.bytes;
    Root bytes(r,r.array_new(r.type("System","Byte"),length));
    r.stat(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",{"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,bytes.get(),&length});
    Root tex(r,r.object_new(r.type("UnityEngine","Texture2D")));P created=nullptr;
    try{
        int side=2,format=4;bool mip=false,discardCPU=true;
        r.call(tex.get(),".ctor",{"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"},{&side,&side,&format,&mip});
        if(!r.unbox<bool>(r.stat(r.type("UnityEngine","ImageConversion"),"LoadImage",{"UnityEngine.Texture2D","System.Byte[]","System.Boolean"},{tex.get(),bytes.get(),&discardCPU})))throw std::runtime_error("Native detail cover decode failed");
        struct {float x,y,w,h;} rect{0,0,float(r.unbox<int>(r.call(tex.get(),"get_width"))),float(r.unbox<int>(r.call(tex.get(),"get_height")))};
        struct {float x,y;} pivot{.5f,.5f};float density=100;
        created=r.stat(r.type("UnityEngine","Sprite"),"Create",{"UnityEngine.Texture2D","UnityEngine.Rect","UnityEngine.Vector2","System.Single"},{tex.get(),&rect,&pivot,&density});
        Root keep(r,created);
        auto weak=std::make_unique<Root>(r,r.object_new(r.type("System","WeakReference")));
        r.call(weak->get(),".ctor",{"System.Object"},{created});cover.weak=std::move(weak);return created;
    }catch(...){if(created)destroy(r,created);destroy(r,tex.get());throw;}
}
std::shared_ptr<Cover> localCover(Batch &next,NSString *identifier){
    NSString *folder=[PMContentStore.shared coverFolder:identifier];
    NSString *path=pmunlock::coverPath(next.r,identifier,false);
    if(!folder.length||!path.length)return {};
    folder=folder.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    path=path.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    if(![path.stringByDeletingLastPathComponent isEqualToString:folder])return {};
    auto k=std::string(path.fileSystemRepresentation);auto hit=next.covers.find(k);if(hit!=next.covers.end())return hit->second;
    // The image stays available if the import is moved or replaced during the
    // scene change. Snapshot each distinct file once, in its original encoding.
    NSData *png=[NSData dataWithContentsOfFile:path options:0 error:nil];
    if(!png.length||png.length>INT32_MAX)return {};
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)png,nullptr);
    if(!source)return {};
    bool valid=CGImageSourceGetCount(source)>0 && CGImageSourceGetStatusAtIndex(source,0)==kCGImageStatusComplete;
    CFRelease(source);if(!valid)return {};
    auto cover=std::make_shared<Cover>();cover->bytes=png;next.covers.emplace(k,cover);return cover;
}
void arraySet(Runtime &r,P array,int i,P value){r.call(array,"SetValue",{"System.Object","System.Int32"},{value,&i});}
std::unique_ptr<Saved> snapshot(Batch &next,P original,P song,int slot,NSDictionary *chart,NSString *group){
    auto &r=next.r;NSString *identifier=chart?chart[@"id"]:group;
    if(![identifier isKindOfClass:NSString.class]||!identifier.length)return {};
    auto art=localCover(next,identifier);
    if(chart&&!art)return {};
    if(!r.get<bool>(original,"visible")||!r.unbox<bool>(r.call(original,"get_Unlocked")))return {};
    // Allocate by whitelist. SongSelectorItem itself has nine Unity scene fields.
    Root row(r,r.object_new(r.klass("SongSelectorItem"))),data(r,r.object_new(r.klass("SongsItem")));
    for(const char *field:{"songsId","songsName","songsTitle","composer","illustrator","songsKey"})r.put(data.get(),field,r.get<P>(song,field));
    r.put(data.get(),"songsId",r.managedString(identifier));
    if(chart){
        NSString *title=chart[@"title"];
        if(![title isKindOfClass:NSString.class]||!title.length)title=identifier;
        r.put(data.get(),"songsKey",r.managedString(identifier));
        for(auto pair:{std::pair<const char*,NSString*>{"songsName",title},{"songsTitle",title},{"composer",chart[@"composer"]},{"illustrator",chart[@"illustrator"]}})
            r.put(data.get(),pair.first,r.managedString(pair.second?:@""));
    }
    for(const char *field:{"difficulty","levels","charter"}){
        P originalArray=r.get<P>(song,field);if(!originalArray||uintptr_t(slot)>=r.array_length(originalArray))return {};
        Root clone(r,r.call(originalArray,"Clone"));r.put(data.get(),field,clone.get());
        if(chart){if(!strcmp(field,"difficulty"))r.arrayPutFloat(clone.get(),slot,PMDifficultyNumber(chart[@"difficulty"]));
            else arraySet(r,clone.get(),slot,r.managedString(!strcmp(field,"levels")?PMDifficultyName(chart[@"level"]):chart[@"charter"]?:@""));}
    }
    P records=r.get<P>(original,"records");if(!records)return {};
    Root list(r,r.object_new(r.object_get_class(records)));r.call(list.get(),".ctor");
    int count=std::max(slot+1,r.unbox<int>(r.call(original,"get_PlayableLevelCount")));if(count>4)return {};
    NSString *recordLevel=chart?PMDifficultyRecordLevel(chart):@[@"EZ",@"HD",@"IN",@"AT"][slot];
    P selected=r.call(r.mainGame(),"GetSongRecord",{"System.String","System.String"},{r.managedString(identifier),r.managedString(recordLevel)});
    for(int i=0;i<count;++i){Root rec(r,r.object_new(r.klass("LevelRecord")));
        if(i==slot&&selected){r.put(rec.get(),"s",r.get<int>(selected,"s"));r.put(rec.get(),"a",r.get<float>(selected,"a"));r.put(rec.get(),"c",r.get<int>(selected,"c"));}
        r.call(list.get(),"Add",{"LevelRecord"},{rec.get()});
    }
    r.put(row.get(),"records",list.get());r.put(row.get(),"songInfo",data.get());
    r.put(row.get(),"visible",true);r.put(row.get(),"<Unlocked>k__BackingField",true);r.put(row.get(),"<PlayableLevelCount>k__BackingField",count);
    r.put(row.get(),"<SelectorTargetWidth>k__BackingField",r.get<int>(original,"<SelectorTargetWidth>k__BackingField"));
    if(art){
        r.put(row.get(),"coverAssetCode",r.managedString([NSString stringWithFormat:@"PM/%@/image@%lu",identifier,(unsigned long)next.revision]));
        r.put(row.get(),"coverBlurAssetCode",r.managedString(pmcontent::selectorThumbnailKey(identifier)));
    }else{
        // Preserve the native per-difficulty cover selection on the detached song.
        bool alternate=r.get<bool>(song,"hasDifferentCover");
        P field=r.field(r.klass("SongsItem"),"differentCover","SongsItem.DifferentDifficulty",false);
        int mask=0;r.field_get_value(song,field,&mask);r.field_set_value(data.get(),field,&mask);
        r.put(data.get(),"hasDifferentCover",alternate);
        P suffix=alternate&&(mask&(1<<slot))?r.arrayAt(r.get<P>(song,"levels"),slot):r.string_new("");
        P builder=r.klass("IdBuilder"),nativeID=r.get<P>(song,"songsId");
        for(auto pair:{std::pair<const char*,const char*>{"coverAssetCode","BuildCoverImageId"},{"coverBlurAssetCode","BuildBlurImageId"}}){
            P address=r.stat(builder,pair.second,{"System.String","System.String"},{nativeID,suffix});
            if(!r.string(address).length)return {};
            r.put(row.get(),pair.first,address);
        }
    }
    return std::make_unique<Saved>(r,row.get(),slot,art);
}
} // namespace
void release(){
    if(!NSThread.isMainThread||!batch)return;
    auto old=std::move(batch);for(auto &it:old->covers){auto &c=*it.second;if(!c.weak)continue;
        try{auto &r=old->r;P s=r.call(c.weak->get(),"get_Target");if(r.alive(s)){P tex=r.call(s,"get_texture");destroy(r,s);destroy(r,tex);}}
        catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
    }
}
static bool currentSelector(Runtime &r,P selector,NSString *chapter,NSUInteger revision){
    if(pmcontent::runtime!=&r||!selector||pmcontent::target(r,pmcontent::loadingSelector)!=selector||!r.alive(selector))return false;
    if(pmcontent::playing||r.get<bool>(selector,"exit")||pmcontent::applied!=revision||PMContentStore.shared.revision!=revision)return false;
    P info=r.get<P>(selector,"nowChapterInfo");
    return info&&[r.string(r.get<P>(info,"chapterCode")) isEqualToString:chapter];
}
bool prepare(Runtime &r,P selector,NSString *chapter,NSArray<NSDictionary *> *entries){
    if(!NSThread.isMainThread)return false;
    release();
    if(![chapter isKindOfClass:NSString.class]||![chapter hasPrefix:@"pm_"]||![entries isKindOfClass:NSArray.class])return false;
    @try{try{
        auto next=std::make_unique<Batch>(r);Batch *staging=next.get();
        if(!currentSelector(r,selector,chapter,next->revision))return false;
        for(id entry in entries){@autoreleasepool{
            @try{try{
                if(![entry isKindOfClass:NSDictionary.class])continue;
                NSString *sid=entry[@"songID"],*diff=entry[@"difficulty"];
                if(![sid isKindOfClass:NSString.class]||!sid.length||(diff&&(![diff isKindOfClass:NSString.class]||!diff.length)))continue;
                Key k=key(sid,diff);if(staging->rows.count(k))continue;
                pmcontent::checkedSong(r,selector,chapter,sid,diff,nil,^BOOL(P row,P song,int slot,NSDictionary *chart,NSString *group){
                    auto saved=snapshot(*staging,row,song,slot,chart,group);
                    if(!saved)return NO;
                    staging->rows.emplace(k,std::move(saved));return YES;
                },true);
            }catch(const std::exception &e){PMDiagnosticsWrite(e.what());}}
            @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
        }}
        if(!currentSelector(r,selector,chapter,next->revision))return false;
        batch=std::move(next);return true;
    }catch(const std::exception &e){PMDiagnosticsWrite(e.what());}}@catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
    return false;
}
bool lookup(NSString *sid,NSString *difficulty,Row &out){
    out={};if(!NSThread.isMainThread||!batch||![sid isKindOfClass:NSString.class]||!sid.length||(difficulty&&![difficulty isKindOfClass:NSString.class]))return false;
    @try{try{if(batch->revision!=PMContentStore.shared.revision)return false;
        auto found=batch->rows.find(key(sid,difficulty));if(found==batch->rows.end())return false;
        Saved &saved=*found->second;P art=saved.cover?sprite(batch->r,*saved.cover):nullptr;
        if(batch->revision!=PMContentStore.shared.revision)return false;
        out={saved.row.get(),saved.slot,art};return true;
    }catch(const std::exception &e){PMDiagnosticsWrite(e.what());}}@catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
    return false;
}
} // namespace pmnativeosrows
