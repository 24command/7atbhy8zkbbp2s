#include "PMNativeOSDetail.hpp"
#import "PMDiagnostics.h"
#include <cmath>
#include <memory>

namespace pmnativedetail {
namespace {
struct Root {
    Runtime &r; uint32_t h=0;
    explicit Root(Runtime &rt):r(rt){}
    ~Root(){if(h)r.gchandle_free(h);}
    Root(const Root&)=delete;
    P get() const {return h?r.gchandle_get_target(h):nullptr;}
    void set(P p){uint32_t next=p?r.gchandle_new(p,false):0;if(p&&!next)throw std::runtime_error("detail: GC handle");if(h)r.gchandle_free(h);h=next;}
};
struct Visit {
    Style style; uint64_t id; Root root,controller,row,originalSongs,privateSongs;
    int selected=0,level=0; bool swapped=false,shown=false,narrow=false;
    Visit(Runtime &r,Style s,uint64_t n):style(s),id(n),root(r),controller(r),row(r),originalSongs(r),privateSongs(r){}
};
std::unique_ptr<Visit> current;
uint64_t sequence=0;
void need(bool condition,const char *message){if(!condition)throw std::runtime_error(message);}
void warn(const char *msg){PMDiagnosticsWrite(msg);}
void setBool(Runtime &r,P o,const char *fn,bool b){r.call(o,fn,{"System.Boolean"},{&b});}
void active(Runtime &r,P obj,bool b){setBool(r,obj,"SetActive",b);}
P gameObject(Runtime &r,P c){return r.call(c,"get_gameObject");}
P member(Runtime &r,P owner,const char *key){P c=r.get<P>(owner,key);need(r.alive(c),key);return c;}
void within(Runtime &r,P root,P c){
    P top=r.call(root,"get_transform"),tr=r.call(c,"get_transform");
    need(tr==top||r.unbox<bool>(r.call(tr,"IsChildOf",{"UnityEngine.Transform"},{top})),"detail: dependency outside private root");
}
void label(Runtime &r,P c,NSString *s){r.call(c,"set_text",{"System.String"},{r.managedString(s?:@"")});}
void validateRow(Runtime &r,P row,int slot){
    need(row&&r.object_get_class(row)==r.klass("SongSelectorItem")&&slot>=0&&slot<4,"detail: invalid row or slot");
    P song=r.get<P>(row,"songInfo");need(song&&r.string(r.get<P>(song,"songsId")).length,"detail: song identity missing");
    need(r.get<bool>(row,"visible")&&r.unbox<bool>(r.call(row,"get_Unlocked"))&&slot<r.unbox<int>(r.call(row,"get_PlayableLevelCount")),"detail: unavailable row/slot");
    for(const char *key:{"difficulty","levels","charter"}){P a=r.get<P>(song,key);need(a&&uintptr_t(slot)<r.array_length(a),key);}
    P records=r.get<P>(row,"records");need(records&&slot<r.count(records)&&r.at(records,slot),"detail: incomplete native records");
}
void inputsOff(Runtime &r,P root){
    // Not just a CanvasGroup: animation events may re-enable raycasts, and
    // uGUI Submit can target a Selectable without raycasting at all.
    for(auto spec: {std::pair<const char*,const char*>{"UnityEngine.UI","GraphicRaycaster"},{"UnityEngine.UI","Selectable"}}){
        P all=r.children(root,r.type(spec.first,spec.second));
        for(uintptr_t i=0;all&&i<r.array_length(all);++i)setBool(r,r.arrayAt(all,int(i)),"set_enabled",false);
    }
}
void c8Speech(Runtime &r,P root,P hint,const Speech &s){
    P content=member(r,hint,"content");within(r,root,content);
    bool show=s.heading.length||s.transcript.length||s.seconds>0;
    active(r,content,show);
    for(const char *key:{"hintLB","hintC","lengthText","contentText","waveDisplay"}){
        P c=member(r,hint,key);within(r,root,c);
        // No authored waveform samples: never show a stock recording's waveform.
        bool visible=show&&strcmp(key,"waveDisplay")&&strcmp(key,"hintLB");
        if(!strcmp(key,"hintC")){visible=s.heading.length;label(r,c,s.heading);}
        if(!strcmp(key,"contentText")){visible=s.transcript.length;label(r,c,s.transcript);}
        if(!strcmp(key,"lengthText")){
            visible=show;int t=int(s.seconds);
            label(r,c,t<60?[NSString stringWithFormat:@"%d\"",t]:[NSString stringWithFormat:@"%d'%d\"",t/60,t%60]);
        }
        active(r,gameObject(r,c),visible);
    }
}
void bindC8(Runtime &r,Visit &v,P row,int slot,P provided){
    P c=v.controller.get(),song=r.get<P>(row,"songInfo"),list=v.privateSongs.get();int index=0;
    r.call(list,"set_Item",{"System.Int32","SongSelectorItem"},{&index,row});
    r.put(c,"selectedSong",index);r.put(c,"nowLevel",slot);
    for(auto pair:{std::pair<const char*,const char*>{"songNameText","songsName"},{"songArtistText","composer"},{"illustratorText","illustrator"}})
        label(r,member(r,c,pair.first),r.string(r.get<P>(song,pair.second)));
    label(r,member(r,c,"charterText"),r.string(r.arrayAt(r.get<P>(song,"charter"),slot)));
    P loader=member(r,c,"songCoverImage"),cover=r.get<P>(row,"coverAssetCode"),low=r.get<P>(row,"coverBlurAssetCode");
    need(r.string(cover).length,"detail: no cover key");r.call(loader,"CheckInitialized");
    if(provided){
        need(r.object_get_class(provided)==r.type("UnityEngine","Sprite")&&r.alive(provided),"detail: exact C8 cover sprite unavailable");
        // Disable only this disposable image loader. Its Image remains visible
        // and cannot be overwritten by a load from the former selector.
        setBool(r,loader,"set_enabled",false);
        r.call(member(r,loader,"_image"),"set_sprite",{"UnityEngine.Sprite"},{provided});
    }else{
        setBool(r,loader,"set_enabled",true);
        if(r.string(low).length)r.call(loader,"SetLowResImage",{"System.String"},{low});
        r.call(loader,"set_Code",{"System.String"},{cover});
    }
    bool jump=true;r.call(c,"UpdateInfo",{"System.Boolean"},{&jump});
    need(r.get<int>(c,"nowLevel")==slot,"detail: native difficulty changed");
}
// Native C9 Open schedules stock-ID cover loads. Never let those coroutines
// overwrite custom art on this disposable presentation controller.
void exactC9Cover(Runtime &r,P c,P row,P provided){
    NSString *code=r.string(r.get<P>(row,"coverAssetCode"));
    if(!provided&&![code hasPrefix:@"PM/"])return;
    P sprite=provided;
    if(!sprite){
        P loader=r.get<P>(row,"cover");
        if(r.alive(loader)&&[r.string(r.call(loader,"get_Code")) isEqualToString:code]&&r.get<bool>(loader,"loadImageOver")){
            P image=member(r,loader,"_image");sprite=r.call(image,"get_sprite");
        }
    }
    need(sprite&&r.object_get_class(sprite)==r.type("UnityEngine","Sprite")&&r.alive(sprite),"detail: exact C9 cover sprite not ready");
    for(const char *name:{"loadCoverImageCoroutine","loadDifferentCoverImageCoroutine"}){
        P job=r.get<P>(c,name);if(job){r.call(c,"StopCoroutine",{"UnityEngine.Coroutine"},{job});r.put<P>(c,name,nullptr);}
    }
    r.call(member(r,c,"songCoverImage"),"set_sprite",{"UnityEngine.Sprite"},{sprite});
}
void dispose(Runtime &r,Visit &v){
    P c=v.controller.get();if(!r.alive(c))return;
    if(v.style==Style::c9){if(v.shown)r.call(c,"Close");return;}
    // Restore the managed list before the coordinator destroys the private donor.
    if(v.swapped&&r.get<P>(c,"songs")==v.privateSongs.get()){
        r.put(c,"songs",v.originalSongs.get());r.put(c,"selectedSong",v.selected);r.put(c,"nowLevel",v.level);
    }
    if(v.shown)setBool(r,member(r,c,"songDetailCanvas"),"set_enabled",false);
}
void cleanup(Runtime &r,Visit &v){@try{try{dispose(r,v);}catch(const std::exception &e){warn(e.what());}}@catch(NSException *e){warn(e.reason.UTF8String);}}
}
P findDonor(Runtime &r,P root,Style style){
    if(!NSThread.isMainThread||!r.alive(root))return nullptr;
    const char *name=style==Style::c8?"Chapter8SelectMusicControl":"Chapter9SongDetailsControl";
    P all=r.children(root,r.klass(name));return all&&r.array_length(all)==1?r.arrayAt(all,0):nullptr;
}
uint64_t open(Runtime &r,Style style,P root,P row,int slot,const Speech &speech,bool narrow,P coverSprite){
    if(!NSThread.isMainThread||current||!std::isfinite(speech.seconds)||speech.seconds<0||speech.seconds>INT32_MAX)return 0;
    if(++sequence==0)++sequence; // token zero is reserved
    auto v=std::make_unique<Visit>(r,style,sequence);
    @try{try{
        validateRow(r,row,slot);P c=findDonor(r,root,style);need(r.alive(c),"detail: donor missing or ambiguous");
        need(r.unbox<bool>(r.call(root,"get_activeInHierarchy")),"detail: donor hierarchy is inactive");
        v->root.set(root);v->controller.set(c);v->row.set(row);v->narrow=narrow;
        if(style==Style::c9){
            for(const char *key:{"titleText","composerText","scoreText","accText","songCoverImage","levelBarController","levelSliderController","ratingDisplayController","animator","canvasGroup","illustrationSizeControl"})within(r,root,member(r,c,key));
            inputsOff(r,root);v->shown=true;r.call(c,"Open",{"SongSelectorItem","System.Int32","System.Boolean"},{row,&slot,&narrow});
            exactC9Cover(r,c,row,coverSprite);
        }else{
            // Host MUST disable this behaviour before its clone first activates.
            // Disabling a live official component invokes its save-writing OnDisable.
            need(!r.unbox<bool>(r.call(c,"get_enabled")),"detail: C8 donor must be disabled before activation");
            for(const char *key:{"songDetailCanvas","songNameText","songArtistText","illustratorText","charterText","songCoverImage","levelBarController","levelSliderController","ratingDisplayController","recordInfoBar","unlockInfoBar","difficulty","level","score","acc","chapter8HintControl","songDetailTweenControl"})within(r,root,member(r,c,key));
            inputsOff(r,root);P list=r.get<P>(c,"songs");need(list,"detail: no native songs list");v->originalSongs.set(list);
            v->selected=r.get<int>(c,"selectedSong");v->level=r.get<int>(c,"nowLevel");
            v->privateSongs.set(r.object_new(r.object_get_class(list)));r.call(v->privateSongs.get(),".ctor");r.call(v->privateSongs.get(),"Add",{"SongSelectorItem"},{row});
            v->swapped=true;r.put(c,"songs",v->privateSongs.get());v->shown=true;
            setBool(r,member(r,c,"songDetailCanvas"),"set_enabled",true);bindC8(r,*v,row,slot,coverSprite);
            int state=1;r.call(member(r,c,"songDetailTweenControl"),"SetState",{"System.Int32"},{&state});
            c8Speech(r,root,member(r,c,"chapter8HintControl"),speech);
        }
        uint64_t id=v->id;current=std::move(v);return id;
    }catch(const std::exception &e){warn(e.what());}}@catch(NSException *e){warn(e.reason.UTF8String);}
    cleanup(r,*v);return 0;
}
bool update(Runtime &r,uint64_t token,P row,int slot,P coverSprite){
    if(!NSThread.isMainThread||!current||current->id!=token||&current->root.r!=&r)return false;
    @try{try{
        validateRow(r,row,slot);Visit &v=*current;P c=v.controller.get();need(r.alive(c)&&r.alive(v.root.get()),"detail: donor unloaded");
        if(v.style==Style::c8)bindC8(r,v,row,slot,coverSprite);
        else if(v.row.get()!=row)r.call(c,"Open",{"SongSelectorItem","System.Int32","System.Boolean"},{row,&slot,&v.narrow});
        else r.call(c,"UpdateInfo",{"SongSelectorItem","System.Int32"},{row,&slot});
        if(v.style==Style::c9)exactC9Cover(r,c,row,coverSprite);
        v.row.set(row);return true;
    }catch(const std::exception &e){warn(e.what());}}@catch(NSException *e){warn(e.reason.UTF8String);}
    close(r,token);return false;
}
void close(Runtime &r,uint64_t token){
    if(!NSThread.isMainThread||!current||current->id!=token||&current->root.r!=&r)return;
    auto v=std::move(current);cleanup(r,*v);
}
}
