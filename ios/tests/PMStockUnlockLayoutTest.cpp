#include "../PhiMod/Sources/PMStockUnlockLayout.hpp"
#include "../PhiMod/Core/PMStockIntroResolver.h"
#include <cassert>
#include <fstream>
#include <string>
#include <limits>
using namespace pmstock;

int main(int argc,char **argv) {
    assert(!layout(4) && !layout(8));
    assert(!PMStockIntroForName("@stock/c5/iga-main"));
    for (int chapter:{0,5,6,7}) {
        const auto &s=*layout(chapter);
        if (chapter) assert(PMStockIntroForName(s.movie));
        Window native{-1,-1};
        assert(native.resolve(s));
        for(double t=native.show;t<=native.hide;t+=1./60) assert(std::abs(native.clipTime(s,t)-t)<1e-8);
        for(Window cue: {Window{0,.025},Window{1,2},Window{51,80}}) {
            assert(cue.resolve(s));
            assert(std::abs(cue.clipTime(s,cue.show)-s.firstAlpha)<1e-8);
            assert(std::abs(cue.clipTime(s,cue.hide)-s.end)<1e-8);
            double previous=s.firstAlpha;
            for(int i=1;i<101;++i) {
                double current=cue.clipTime(s,cue.show+(cue.hide-cue.show)*i/100);
                assert(current>=previous && current<s.end+1e-8);
                previous=current;
            }
        }
        for (Window bad:{Window{1,1},Window{-2,3},Window{4,2},Window{NAN,2},Window{2,INFINITY}})
            assert(!bad.resolve(s));
        // Optional argument: directory containing the original sharedassets*.assets.
        if(argc>1) {
            std::ifstream in(std::string(argv[1])+"/sharedassets"+std::to_string(s.scene)+".assets",std::ios::binary);
            in.seekg(s.streamOffset);
            std::vector<uint8_t> data(s.streamSize);
            in.read(reinterpret_cast<char *>(data.data()),data.size());
            assert(in);
            Curves c;
            assert(c.load(data.data(),data.size(),s.lanes));
            assert(std::abs(c.sample(2,s.firstAlpha))<.0001);
            assert(std::abs(c.sample(2,s.firstAlpha+.5)-1)<.0001);
            assert(std::abs(c.sample(2,s.end))<.0001);
            assert(std::abs(c.sample(0,s.firstAlpha+1))<.001);
            assert(std::abs(c.sample(1,s.firstAlpha+1))<.001);
            if(chapter==7) assert(c.sample(3,24)>.55 && c.sample(3,26.5)<.12);
            assert(!c.load(data.data(),data.size()-1,s.lanes));
        }
    }
    // Two frames on one lane and the Unity final +inf frame. Cubic coefficients
    // implement value = 2t^3 + 3t^2 + 4t + 5 for t in [0,1).
    uint32_t bytes[]={0,1,0,0x40000000,0x40400000,0x40800000,0x40a00000,
                      0x3f800000,1,0,0,0,0,0x41600000,0x7f800000,0};
    Curves c;
    assert(c.load(reinterpret_cast<uint8_t*>(bytes),sizeof(bytes),1));
    assert(c.sample(0,.5)==8 && c.sample(0,1)==14 && c.sample(0,0)==5);
    bytes[2]=1;
    assert(!c.load(reinterpret_cast<uint8_t*>(bytes),sizeof(bytes),1));
}
