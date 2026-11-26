// Compile the production additive adapter, not a reimplementation of its state.
#include "../PhiMod/Sources/PMNativeOSMapBlend.hpp"
#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
namespace blend=pmnativeosmap::blend;
namespace layout=pmnativeosmap::layout;
using Handle=uint32_t;
struct Color { float red,green,blue,alpha; };
struct Managed {
    Managed *klass=nullptr,*shader=nullptr,*material=nullptr;
    float alpha=1;
    Color color{1,1,1,1};
    bool alive=true,ignore=false,raycast=true,interactable=true,value=false;
    std::string name;
};
using P=Managed *;
struct Runtime {
    std::vector<std::unique_ptr<Managed>> objects;
    std::vector<std::string> calls;
    P shaderType,materialType,resourcesType,shader;
    bool missing=false,wrongType=false,unsupported=false,badBinding=false;
    int loads=0,constructs=0;
    Runtime() {
        shaderType=make();materialType=make();resourcesType=make();shader=make();shader->klass=shaderType;
    }
    P make() { objects.emplace_back(new Managed); return objects.back().get(); }
    P type(const char *ns,const char *name) {
        assert(std::string(ns)=="UnityEngine");
        if (std::string(name)=="Shader") return shaderType;
        if (std::string(name)=="Material") return materialType;
        assert(std::string(name)=="Resources");return resourcesType;
    }
    P string_new(const char *name) { P p=make();p->name=name;return p; }
    P class_get_type(P p) {return p;}
    P type_get_object(P p) {return p;}
    P object_get_class(P p) {return p->klass;}
    P object_new(P type) {P p=make();p->klass=type;return p;}
    bool alive(P p) {return p && p->alive;}
    template<class T> T unbox(P p) {return T(p->value);}
    P stat(P type,const char *method,std::initializer_list<const char *> types,std::initializer_list<void *> args) {
        assert(type==resourcesType && std::string(method)=="Load" && types.size()==2);
        auto a=args.begin();assert(static_cast<P>(*a)->name==blend::shaderResource && *(a+1)==shaderType);
        ++loads;if(missing)return nullptr;
        shader->klass=wrongType ? materialType : shaderType;return shader;
    }
    P call(P p,const char *name,std::initializer_list<const char *> = {},std::initializer_list<void *> args = {}) {
        assert(p);std::string method=name;calls.push_back(method);auto a=args.begin();
        if(method=="get_isSupported") {P b=make();b->value=!unsupported;return b;}
        if(method==".ctor") {++constructs;p->shader=badBinding?nullptr:static_cast<P>(*a);return nullptr;}
        if(method=="get_shader")return p->shader;
        if(method=="set_alpha")p->alpha=*static_cast<float *>(*a);
        else if(method=="set_ignoreParentGroups")p->ignore=*static_cast<bool *>(*a);
        else if(method=="set_blocksRaycasts")p->raycast=*static_cast<bool *>(*a);
        else if(method=="set_interactable")p->interactable=*static_cast<bool *>(*a);
        else if(method=="set_color")p->color=*static_cast<Color *>(*a);
        else if(method=="set_material")p->material=static_cast<P>(*a);
        else throw std::runtime_error("unexpected call: "+method);
        return nullptr;
    }
};
struct Item {
    blend::Layer additive;
    bool active=true,locked=false;
    float inheritedAlpha=1;
};
struct Map {
    Runtime r;
    std::vector<P> handles{nullptr};
    std::vector<Handle> assets;
    std::vector<Item> items;
    Handle additiveMaterial=0,rootGroup=0;
    bool hasAdditive=false,input=false;
    float rootOpacity=0;
    Map() {rootGroup=keep(r.make());}
    Handle keep(P p) {assert(p);handles.push_back(p);return Handle(handles.size()-1);}
    P get(Handle h) {return handles.at(h);}
};
void flag(Runtime &r,P p,const char *method,bool value) {r.call(p,method,{"System.Boolean"},{&value});}
P add(Runtime &r,P,const char *ns,const char *name) {
    assert(std::string(ns)=="UnityEngine" && std::string(name)=="CanvasGroup");return r.make();
}
#include "../PhiMod/Sources/PMNativeOSMapBlend.inc"
static bool near(double a,double b) {return std::abs(a-b)<2e-7;}
static void algebraAndEncodedTexture() {
    // Straight RGB/alpha from source run: stored.rgb=accumulated/maxChannel,
    // stored.a=maxChannel. The texture's alpha must appear exactly once.
    for(float inherited:{0.f,.001f,.1f,.25f,.5f,1.f})
    for(float tint:{0.f,.1f,.5f,1.f})
    for(float root:{0.f,.25f,1.f}) {
        float a=blend::groupAlpha(inherited,tint,root,true);
        assert(a>=0 && a<=1);
        double encodedAlpha=.6, rgb=.3/.6, tintRGB=.7;
        double actual=(rgb*tintRGB*a)*(encodedAlpha*a);
        double expected=.3*tintRGB*inherited*tint*root;
        assert(near(actual,expected));
        assert(blend::groupAlpha(inherited,tint,root,false)==0);
    }
    assert(near(blend::groupAlpha(.25,1,1,true),.5)); // Not .25 -> alpha squared.
    assert(blend::groupAlpha(1,1,0,true)==0);
    assert(blend::groupAlpha(std::numeric_limits<float>::quiet_NaN(),1,1,true)==0);
    assert(blend::groupAlpha(2,2,2,true)==1);
    assert(blend::groupAlpha(-1,1,1,true)==0);
    auto p=layout::sample(layout::opacity(1,0,8,2)*.5f,true,true,true,1);
    auto c=layout::sample(layout::opacity(1,0,4,2)*.8f,true,true,p.active,p.inherited);
    assert(near(p.inherited,.25) && near(c.inherited,.1));
    float a=blend::groupAlpha(c.inherited,.4f,1,c.active);
    assert(near(a*a,.04));
    assert(!layout::sample(1,true,false,true,1).active);
    assert(!layout::sample(1,false,true,true,1).active);
    assert(!layout::sample(1,true,true,false,1).active);
    assert(!layout::sample(layout::opacity(4,0,4,0),true,true,true,1).active);
}
static void tintAndNormalCompatibility() {
    blend::Layer normal,additive;additive.group=7;
    Color color{.3f,.8f,.2f,.4f};
    auto old=blend::graphicColor(normal,color);
    assert(old.red==color.red && old.alpha==.4f && normal.tintAlpha==1);
    // Legacy color belongs to the backing, even for additive opacity-only tracks.
    auto background=blend::graphicColor(additive,color,false);
    assert(background.alpha==.4f && additive.tintAlpha==1);
    auto vertex=blend::graphicColor(additive,color);
    assert(vertex.red==.3f && vertex.green==.8f && vertex.blue==.2f && vertex.alpha==1);
    assert(additive.tintAlpha==.4f);
    auto a=blend::groupAlpha(.5f,additive.tintAlpha,1,true);
    assert(near(a*a,.2));
    vertex=blend::graphicColor(additive,Color{1,1,1,0});
    assert(vertex.alpha==1 && additive.tintAlpha==0);
}
static void materialAndRootLifecycle() {
    Map m;m.items.resize(3);
    auto child0=m.keep(m.r.make()),graphic0=m.keep(m.r.make());
    bindAdditive(m,m.items[0].additive,child0,graphic0);
    auto group=m.get(m.items[0].additive.group);
    assert(group!=m.get(m.rootGroup) && group->alpha==0 && group->ignore);
    assert(!group->raycast && !group->interactable && m.get(graphic0)->color.alpha==1);
    assert(m.r.loads==1 && m.r.constructs==1 && m.assets.size()==1);
    assert(m.get(m.assets[0])->klass==m.r.materialType && m.get(m.assets[0])!=m.r.shader);
    // First zero must precede enabling ignoreParentGroups.
    auto zero=std::find(m.r.calls.begin(),m.r.calls.end(),"set_alpha");
    auto ignore=std::find(m.r.calls.begin(),m.r.calls.end(),"set_ignoreParentGroups");
    assert(zero<ignore);
    auto child1=m.keep(m.r.make()),graphic1=m.keep(m.r.make());
    bindAdditive(m,m.items[1].additive,child1,graphic1);
    assert(m.r.loads==1 && m.r.constructs==1 && m.assets.size()==1);
    assert(m.get(graphic0)->material==m.get(graphic1)->material);
    m.items[0].inheritedAlpha=.25f;
    m.items[0].additive.tintAlpha=.36f;
    m.items[1].inheritedAlpha=.5f;
    // Covered warmup: root is alive, layers remain zero even with positive author alpha.
    setRootOpacity(m,0);syncAdditive(m,m.items[0]);assert(group->alpha==0);
    m.input=true;setRootOpacity(m,1);assert(near(group->alpha,.3));assert(group->raycast);
    auto count=m.r.calls.size();syncAdditive(m,m.items[0]);assert(count==m.r.calls.size());
    // Paused visible view keeps light, but ignoreParentGroups cannot leak input.
    m.input=false;syncAdditive(m,m.items[0]);assert(near(group->alpha,.3) && !group->raycast);
    m.input=true;setRootOpacity(m,0);assert(group->alpha==0 && !group->raycast);
    setRootOpacity(m,1);assert(near(group->alpha,.3));
    // displayPage clears old layers before the subsequent refresh samples screens.
    hideAdditive(m);assert(group->alpha==0 && !group->raycast);
    m.items[0].active=false;syncAdditive(m,m.items[0]);assert(group->alpha==0);
    m.items[0].active=true;syncAdditive(m,m.items[0]);assert(near(group->alpha,.3));
    m.items[0].locked=true;syncAdditive(m,m.items[0]);assert(!group->raycast);
    hideAdditive(m);hideAdditive(m);assert(group->alpha==0);
    // Normal node makes no additive managed calls.
    count=m.r.calls.size();syncAdditive(m,m.items[2]);assert(count==m.r.calls.size());
    Map plain;plain.items.resize(1);syncAdditive(plain,plain.items[0]);hideAdditive(plain);
    assert(plain.r.loads==0 && plain.r.constructs==0 && plain.r.calls.empty());
}
static void failClosed() {
    for(int mode=0;mode<4;++mode) {
        Map m;m.r.missing=mode==0;m.r.wrongType=mode==1;m.r.unsupported=mode==2;m.r.badBinding=mode==3;
        blend::Layer layer;bool threw=false;
        try {bindAdditive(m,layer,m.keep(m.r.make()),m.keep(m.r.make()));}
        catch(const std::runtime_error &e) {threw=true;assert(std::strstr(e.what(),"Map additive blend:"));}
        assert(threw && !m.hasAdditive && !layer.group && !m.additiveMaterial);
        assert(m.assets.size()==(mode==3 ? 1u : 0u)); // Partial private object is owned for failure cleanup.
    }
}
int main() {
    algebraAndEncodedTexture();tintAndNormalCompatibility();materialAndRootLifecycle();failClosed();
    std::cout<<"Additive blend: 4 numerical/native adapter suites passed\n";
}
