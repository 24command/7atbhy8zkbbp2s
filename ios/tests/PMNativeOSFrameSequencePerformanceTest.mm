// Compiled with real Foundation/ImageIO and the production MapMedia adapter.
// Only the managed Unity boundary is substituted with an audited recorder.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include "PMNativeOSMapPortableUnderTest.inc"
#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include "../PhiMod/Sources/PMNativeOSFrameSequence.hpp"
#include <cassert>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
namespace layout=pmnativeosmap::layout;
namespace rendering=pmnativeosmap::rendering;
namespace residency=pmnativeosmap::residency;
namespace readiness=pmnativeosmap::readiness;
namespace playback=pmnativeosmap::playback;
namespace blend=pmnativeosmap::blend;
using Handle=uint32_t;
struct Managed {
    std::string kind;
    bool alive=true, enabled=false;
    int width=0,height=0;
    long long value=0;
    Managed *texture=nullptr;
    std::vector<unsigned char> bytes;
};
using P=Managed *;
struct Runtime {
    std::vector<std::unique_ptr<Managed>> objects;
    std::map<Handle,P> roots;
    Handle next=0;
    int uploads=0, applies=0, constructs=0, destroys=0, resizes=0, plays=0, stops=0;
    P make(const std::string &kind="") {objects.emplace_back(new Managed);objects.back()->kind=kind;return objects.back().get();}
    P type(const char *,const char *name) {return make(name);}
    P object_new(P cls) {return make(cls->kind);}
    Handle gchandle_new(P p,bool) {roots[++next]=p;return next;}
    void gchandle_free(Handle h) {assert(roots.erase(h)==1);}
    P gchandle_get_target(Handle h) {return roots.at(h);}
    bool alive(P p) {return p && p->alive;}
    P managedString(NSString *) {return make("String");}
    template<class T> T unbox(P p) {assert(p);return T(p->value);}
    P boxed(long long n) {P p=make();p->value=n;return p;}
    P stat(P,const char *name,std::initializer_list<const char *>,std::initializer_list<void *> args) {
        assert(std::string(name)=="Destroy");P p=static_cast<P>(*args.begin());assert(p && p->alive);
        p->alive=false;++destroys;return nullptr;
    }
    P call(P p,const char *name,std::initializer_list<const char *> types={},std::initializer_list<void *> args={}) {
        assert(p && p->alive);std::string method=name;auto a=args.begin();
        if(method==".ctor" || method=="Reinitialize") {
            assert(p->kind=="Texture2D" && args.size()==4);
            assert(*static_cast<int *>(a[2])==4 && !*static_cast<bool *>(a[3]));
            p->width=*static_cast<int *>(a[0]);p->height=*static_cast<int *>(a[1]);
            if(method==".ctor")++constructs;else ++resizes;
            return boxed(true);
        }
        if(method=="LoadRawTextureData") {
            assert(types.size()==2 && std::string(*types.begin())=="System.IntPtr");
            auto bytes=*static_cast<const unsigned char **>(a[0]);int count=*static_cast<int *>(a[1]);
            assert(count==p->width*p->height*4);p->bytes.assign(bytes,bytes+count);++uploads;return nullptr;
        }
        if(method=="Apply") {assert(args.size()==2 && !*static_cast<bool *>(a[0]) && !*static_cast<bool *>(a[1]));++applies;return nullptr;}
        if(method=="set_texture" || method=="set_sprite") {p->texture=static_cast<P>(a[0]);return nullptr;}
        if(method=="set_enabled") {p->enabled=*static_cast<bool *>(a[0]);return nullptr;}
        if(method=="get_texture")return p->texture;
        if(method=="get_width")return boxed(p->width);
        if(method=="get_height")return boxed(p->height);
        if(method=="get_isPrepared")return boxed(true);
        if(method=="get_frame")return boxed(0);
        if(method=="Play") {++plays;return nullptr;}
        if(method=="Stop") {++stops;p->texture=nullptr;return nullptr;}
        if(method=="Pause" || method=="Prepare" || method.rfind("set_",0)==0)return nullptr;
        throw std::runtime_error("unexpected managed call: "+method);
    }
};
struct Art {Handle sprite=0,silhouette=0;float aspect=1;};
struct Item {
    NSString *artPath=nil;
    Handle image=0,fitter=0,flash=0,flashSprite=0,silhouette=0;
    int flashFace=-1;
    bool artLoaded=false,artReadable=false,artMask=false;
};
struct Map {
    Runtime r;
    std::vector<Handle> handles,assets,pageAssets;
    std::map<std::string,Art> pageArt;
    std::vector<int> pagePixels;
    std::vector<Item> items;
    int page=0;
    Handle keep(P p) {Handle h=r.gchandle_new(p,false);handles.push_back(h);return h;}
    P get(Handle h) {return h ? r.gchandle_get_target(h) : nullptr;}
};
void flag(Runtime &r,P p,const char *name,bool v) {r.call(p,name,{"System.Boolean"},{&v});}
P add(Runtime &r,P,const char *,const char *name) {return r.make(name);}
struct Object {Handle go,rect;};
Object child(Map &m,P,const char *) {return {m.keep(m.r.make("GameObject")),m.keep(m.r.make("RectTransform"))};}
void stretch(Runtime &,P) {}
P fit(Runtime &r,P,float,bool) {return r.make("Fitter");}
void bindAdditive(Map &,blend::Layer &,Handle,Handle) {}
void PMDiagnosticsWrite(const char *) {}
template<class Work> bool checked(Work work,NSString **reason=nullptr) {
    try {work();return true;} catch(const std::exception &e) {if(reason)*reason=[NSString stringWithUTF8String:e.what()];return false;}
}
#include "PMNativeOSMapOwnershipUnderTest.inc"
NSData *encodeImage(CGImageRef) {throw std::runtime_error("PMA must never encode PNG");}
void upload(Runtime &,P,NSData *,bool) {throw std::runtime_error("PMA must never call LoadImage");}
#include "../PhiMod/Sources/PMNativeOSMapMedia.inc"
int stillLoads=0;
Art loadArt(Map &m,NSString *,int pixels,bool,bool mask) {
    ++stillLoads;Art a; // acquisition lifecycle uses the production cache/ownership code
    a.sprite=newTexture(m,pixels,pixels);
    if(mask)a.silhouette=newTexture(m,pixels,pixels);
    return a;
}
#include "PMNativeOSMapResidencyUnderTest.inc"
static void png(NSString *path,size_t width,size_t height) {
    // Explicit top row red, bottom row half-alpha blue. No draw-coordinate
    // ambiguity in the source fixture; CGImage data is top-to-bottom.
    NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];
    auto *p=static_cast<unsigned char *>(pixels.mutableBytes);
    for(size_t y=0;y<height;++y)for(size_t x=0;x<width;++x) {
        size_t i=(y*width+x)*4;
        if(y<height/2){p[i]=255;p[i+3]=255;}
        else {p[i+2]=128;p[i+3]=128;}
    }
    CGColorSpaceRef rgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,rgb,
        kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast,provider,nullptr,false,kCGRenderingIntentDefault);
    assert(image);
    CGImageDestinationRef dest=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,nullptr);
    assert(dest);CGImageDestinationAddImage(dest,image,nullptr);assert(CGImageDestinationFinalize(dest));
    CFRelease(dest);CGImageRelease(image);CGDataProviderRelease(provider);CGColorSpaceRelease(rgb);
}
static NSString *manifest(NSString *dir,NSUInteger size,NSArray *frames) {
    NSString *path=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.pma",(unsigned long)size]];
    NSDictionary *doc=@{@"version":@1,@"width":@(size),@"height":@(size),@"fps":@30,@"frames":frames};
    assert([[NSJSONSerialization dataWithJSONObject:doc options:0 error:nil] writeToFile:path atomically:YES]);return path;
}
static void budgets() {
    auto page=std::make_unique<PMOSPage>();page->nodes=253;page->screens=2;page->initialScreen=0;
    NSMutableArray *models=[NSMutableArray array];
    for(int i=0;i<253;++i) {
        auto &n=page->elements[i];n.screen=i<5?0:1;n.parent=n.dropIndex=-1;n.kind=PMOSImage;
        [models addObject:@{@"path":[NSString stringWithFormat:@"/os-media/%d.pma",i]}];
    }
    auto limits=preflight(*page,models,[NSMutableSet set]);
    assert(limits[0]>=720 && limits[1]<140); // the other 248 nodes cost this page nothing
    assert(size_t(limits[0])*limits[0]*5<=residency::pageTexels);
    assert(size_t(limits[1])*limits[1]*248<=residency::pageTexels);
    page->elements[0].songSuppressed=true;
    assert(preflight(*page,models,[NSMutableSet set])[0]==residency::dimensionLimit(4));
    page->elements[0].songSuppressed=false;
    page->entryTransition.declared=true;page->entryTransition.kind=PMOSEntryTransitionTimeline;page->entryTransition.screen=1;
    auto reserved=preflight(*page,models,[NSMutableSet set]);
    assert(reserved[0]==limits[0] && reserved[1]==2048);
    page->entryTransition.declared=false;
    page->nodes=5;[models removeObjectsInRange:NSMakeRange(5,248)];
    assert(preflight(*page,models,[NSMutableSet set])[0]==limits[0]);
    // Distinct stills share one texture; a named silhouette gets its own slot.
    for(int i=0;i<5;++i)models[i]=@{@"path":@"/os-media/shared.png"};
    auto masks=[NSMutableSet setWithObject:pageArtKey(1,@"/os-media/shared.png")];
    assert(preflight(*page,models,masks)[0]==residency::dimensionLimit(1)); // other page's mask is free
    [masks addObject:pageArtKey(0,@"/os-media/shared.png")];
    assert(preflight(*page,models,masks)[0]==residency::dimensionLimit(2));
    page->elements[0].songSuppressed=true;
    assert(preflight(*page,models,masks)[0]==residency::dimensionLimit(2));
}
static void cacheAndPixels(NSString *dir) {
    for(NSUInteger size:{360u,720u}) {
        NSString *name=[NSString stringWithFormat:@"%lu.png",(unsigned long)size];
        NSString *file=[dir stringByAppendingPathComponent:name];png(file,size,size);
        NSString *path=manifest(dir,size,@[name,name]);NSError *error=nil;
        NSObject *sequence=PMOSFrameSequenceOpen(path,&error);assert(sequence && !error);
        NSUInteger w=0,h=0;uint64_t rev=0;
        NSData *rgba=PMOSFrameSequenceRGBAFrame(sequence,0,915,&w,&h,&rev,&error);
        assert(rgba && !error && w==size && h==size && rgba.length==size*size*4 && rev==1);
        const auto *p=static_cast<const unsigned char *>(rgba.bytes);
        assert(p[0]<=1 && p[1]<=1 && p[2]>=253 && p[3]==128); // bottom, straight alpha
        size_t top=(h-1)*w*4;assert(p[top]==255 && p[top+1]==0 && p[top+2]==0 && p[top+3]==255);
        // Removing the file proves a repeated filename does not even reread it.
        assert([NSFileManager.defaultManager removeItemAtPath:file error:nil]);
        uint64_t repeat=0;
        assert(PMOSFrameSequenceRGBAFrame(sequence,1,915,&w,&h,&repeat,&error)==rgba && repeat==rev);
        png(file,size,size);
        __weak NSData *previous=nil;
        @autoreleasepool {
            NSData *smaller=PMOSFrameSequenceRGBAFrame(sequence,1,180,&w,&h,&repeat,&error);
            assert(smaller && w==180 && h==180 && repeat==rev+1);previous=smaller;
        }
        assert(previous); // exactly the current decoder cache keeps this alive
        @autoreleasepool {assert(PMOSFrameSequenceRGBAFrame(sequence,0,915,&w,&h,&repeat,&error));}
        assert(!previous && repeat==rev+2); // replacing the cache released the old frame
    }
    NSString *path=manifest(dir,360,@[@"360.png",@"720.png"]);NSError *error=nil;
    NSObject *sequence=PMOSFrameSequenceOpen(path,&error);assert(sequence);
    assert(!PMOSFrameSequenceRGBAFrame(sequence,1,915,nullptr,nullptr,nullptr,&error) && error);
}
static void textures(NSString *dir) {
    Map m;
    auto media=buildMedia(m,nullptr,manifest(dir,720,@[@"720.png",@"720.png"]),false,true,915);
    assert(!media->texture && m.r.constructs==0); // inactive page allocates no texture
    const size_t baseline=m.r.roots.size();
    for(int visit=0;visit<20;++visit) {
        media->gif=std::make_shared<GifVisit>();auto &g=*media->gif;
        NSObject *decoder=PMOSFrameSequenceOpen(media->path,nullptr);assert(decoder);
        g.ready=PMOSFrameSequenceRGBAFrame(decoder,0,915,&g.width,&g.height,&g.revision,nullptr);
        int before=m.r.uploads;P texture=uploadSequence(m,*media);
        assert(texture->width==720 && texture->height==720 && m.r.uploads==before+1);
        assert(m.r.applies==m.r.uploads && m.r.resizes==0);
        attachMedia(m,*media,texture,1);g.ready=nil;
        g.ready=PMOSFrameSequenceRGBAFrame(decoder,1,915,&g.width,&g.height,&g.revision,nullptr);
        assert(uploadSequence(m,*media)==texture && m.r.uploads==before+1);
        auto weak=std::weak_ptr<GifVisit>(media->gif);
        stopMedia(m,*media);
        assert(weak.expired() && !media->texture && !m.get(media->raw)->texture && !texture->alive);
        assert(m.assets.empty() && m.r.roots.size()==baseline && m.handles.size()==baseline);
        stopMedia(m,*media); // idempotent retirement
    }
    assert(m.r.constructs==20 && m.r.destroys==20);
    media->gif=std::make_shared<GifVisit>();auto &g=*media->gif;
    g.width=720;g.height=720;g.ready=[NSData dataWithBytes:"bad" length:3];
    bool rejected=false;try {uploadSequence(m,*media);}catch(const std::exception &){rejected=true;}
    assert(rejected && !media->texture && m.assets.empty());
    stopMedia(m,*media);
    // Still cache shares only within one page and releases both sprites/masks.
    m.pagePixels={915,130};m.items.resize(2);
    for(auto &i:m.items){i.artPath=@"/shared.png";i.artMask=true;i.image=m.keep(m.r.make());i.fitter=m.keep(m.r.make());}
    const size_t stillBaseline=m.r.roots.size();
    for(int page=0;page<10;++page){m.page=page%2;acquireArt(m,m.items[0]);acquireArt(m,m.items[1]);
        assert(m.pageArt.size()==1 && m.pageAssets.size()==2);
        assert(m.items[0].silhouette==m.items[1].silhouette);
        releasePageArt(m);assert(m.pageAssets.empty() && m.assets.empty() && m.r.roots.size()==stillBaseline);
        assert(!m.items[0].artLoaded && !m.items[0].silhouette && !m.get(m.items[0].image)->texture);
    }
    assert(stillLoads==10);
}
static void pumpUntil(const std::function<bool()> &done) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];
    while(!done() && limit.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    assert(done());
}
static void queuedCancellation(NSString *dir) {
    Map m;auto media=buildMedia(m,nullptr,manifest(dir,720,@[@"720.png",@"720.png"]),false,true,915);
    auto queue=gifDecodeQueue();dispatch_suspend(queue);
    for(int visit=0;visit<64;++visit) {
        media->gif=std::make_shared<GifVisit>();
        std::weak_ptr<GifSource> decoder=media->gif->decoder;
        requestGif(*media);
        std::weak_ptr<GifDelivery> delivery=media->gif->delivery;
        stopMedia(m,*media);
        assert(decoder.expired() && delivery.expired());
    }
    dispatch_resume(queue);
    dispatch_sync(queue,^{}); // cancelled jobs skip without decoding or posting bytes
    assert(m.r.uploads==0 && m.r.constructs==0 && m.assets.empty());
}
static void playbackAndCancellation(NSString *dir) {
    Map m;auto media=buildMedia(m,nullptr,manifest(dir,720,@[@"720.png",@"720.png"]),false,true,915);
    warmMedia(m,*media,false);assert(media->gif && media->gif->pending && !media->texture);
    pumpUntil([&]{return !media->gif->pending;});
    warmMedia(m,*media,false);assert(media->first.held() && m.r.uploads==1);
    P first=m.get(media->texture);
    syncMedia(m,*media,true,10);assert(media->playing && media->gif->pending);
    pumpUntil([&]{return !media->gif->pending;});
    syncMedia(m,*media,true,10.04);
    assert(m.r.uploads==1 && m.get(media->texture)==first); // repeated file advances clock, zero upload
    assert(media->gif->sequenceClock.shown.frame==1);
    // There is now a queued next-lap request. Cancel and reenter immediately;
    // stale work must not mutate or reattach the old visit's destroyed texture.
    std::weak_ptr<GifVisit> old=media->gif;
    stopMedia(m,*media);assert(old.expired() && !first->alive);
    warmMedia(m,*media,false);
    pumpUntil([&]{return !media->gif->pending;});
    warmMedia(m,*media,false);
    assert(media->first.held() && m.r.uploads==2 && m.get(media->texture)!=first);
    stopMedia(m,*media);assert(m.assets.empty());
}
int main(){@autoreleasepool {
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:[@".pma-performance-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *dir=[root stringByAppendingPathComponent:@"os-media"];
    assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    budgets();cacheAndPixels(dir);textures(dir);queuedCancellation(dir);playbackAndCancellation(dir);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    puts("PMA performance: actual adapter, native dimensions/alpha/orientation, repeat cache, page budget and texture lifecycle passed");
}}
