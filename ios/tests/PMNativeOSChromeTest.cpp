#include <initializer_list>
#include "../PhiMod/Sources/PMNativeOSChrome.hpp"
using namespace pmnativechrome;
constexpr bool routes() {
    for (bool allowList:{false,true}) for (bool input:{false,true}) {
        for (Face face:{Face::Hidden,Face::Map,Face::Detail}) {
            bool shown=allowList && face==Face::Map;
            if(policy::visible(face,Intent::List,allowList)!=shown ||
               policy::enabled(face,input,15,{Intent::List},allowList)!=(shown && input)) return false;
            for (Intent other:{Intent::Back,Intent::Start,Intent::Slot}) {
                if(policy::visible(face,other,false)!=policy::visible(face,other,true)) return false;
                if(policy::enabled(face,input,15,{other,1},false)!=policy::enabled(face,input,15,{other,1},true)) return false;
            }
        }
    }
    for (unsigned bits=0;bits<16;++bits) for(int slot=-1;slot<=4;++slot) {
        Press p{Intent::Slot,slot};
        if(policy::enabled(Face::Detail,true,bits,p)!=(slot>=0 && slot<4 && bool(bits & (1u<<slot)))) return false;
        if(policy::enabled(Face::Detail,false,bits,p) || policy::enabled(Face::Map,true,bits,p)) return false;
    }
    for (Intent action:{Intent::Back,Intent::List,Intent::Start,Intent::Slot})
        if(policy::enabled(Face::Hidden,true,15,{action,0})) return false;
    return policy::visible(Face::Map,Intent::Back) && policy::visible(Face::Detail,Intent::Back) &&
           policy::visible(Face::Map,Intent::List) && !policy::visible(Face::Detail,Intent::List) &&
           policy::visible(Face::Detail,Intent::Start) && !policy::visible(Face::Map,Intent::Start) &&
           !policy::visible(Face::Detail,Intent::Pass) && !policy::visible(Face::Map,Intent::Consumed);
}
static_assert(routes(),"native chrome routing contract");
int main() { return !routes(); }
