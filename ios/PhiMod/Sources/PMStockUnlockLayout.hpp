#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace pmstock {
struct Layout {
    int chapter, scene;
    const char *movie;
    double firstAlpha, exitStart, end;
    const char *sceneHash;
    std::array<unsigned,4> polygons; // SongInfoBar, Line, SongNameBar, Level (LeanPolygon objects)
    unsigned streamOffset, streamSize, lanes;
    const char *streamHash;
};
inline const Layout *layout(long chapter) {
    static constexpr Layout layouts[] = {
        {0,8,nullptr,62./60,6.5,7,
         "5a7da615d947bb9868caf184c8d2988d01c419675b6f657019d60b64df575f3a",{22440,23424,22720,21224},12140,7312,3,
         "3070dd48d2827a040c145ee8e8ce14986060cb738535928cd08d149063d7928e"},
        {5,14,"@stock/c5/spas-unlock",212./60,1078./60,1108./60,
         "86c5ccf2720fdec5273807f26ca4ea3745f40693d19338530b22f6e689dc5d76",{14280,17200,13840,15840},10440,7312,3,
         "175d13897cb4c541dbbf025b67c56cf092084fd64724b20ab9af87254e6ead73"},
        {6,15,"@stock/c6/iga-main",659./60,16.3,16.8,
         "23ac95e582172c2df58365ed3332e6b410f0de38d0243cf57e8fe45099da2608",{10064,12504,12184,12784},2384,7312,3,
         "385f5d76afadec647d0b72d1f34a36dfffd77542a770171a1802d73b63cc30ee"},
        {7,20,"@stock/c7/rrharil-unlock",908./60,28.95,1757./60,
         "df0dcf065f266c1d7406e7c1ec6a8361b11043b0d6bde4c63be9661351ee094b",{19712,18032,15824,16408},395520,9648,10,
         "b2ad297f2e3e623f5f32a776307118adfc777cfbf8e5199801b4155ca8c55235"},
    };
    for (auto &s : layouts) if (s.chapter == chapter) return &s;
    return nullptr;
}
struct Window {
    double show, hide;
    bool resolve(const Layout &s) {
        if (show == -1) show = s.firstAlpha;
        if (hide == -1) hide = s.end;
        return std::isfinite(show) && std::isfinite(hide) && show >= 0 && show < hide &&
               hide <= 86400.;
    }
    // Preserve entry/exit speed for normal windows. Compress them proportionally
    // for brief cues, stretching just the fully revealed section otherwise.
    double clipTime(const Layout &s,double t) const {
        const double entry = 1., exit = s.end - s.exitStart;
        const double span = hide-show;
        if (span <= entry+exit) {
            double phase = ((t-show)/span)*(entry+exit);
            return phase <= entry ? s.firstAlpha+phase : s.exitStart+phase-entry;
        }
        if (t <= show+entry) return s.firstAlpha+(t-show);
        if (t >= hide-exit) return s.end-(hide-t);
        double fraction = (t-show-entry)/(span-entry-exit);
        return s.firstAlpha + entry + fraction*(s.exitStart-s.firstAlpha-entry);
    }
};
template<typename T> inline T read(const uint8_t *p) { T v; std::memcpy(&v,p,sizeof(v)); return v; }
struct Key { float time, a,b,c,d; };
struct Curves {
    std::array<std::vector<Key>,10> lanes;
    bool load(const uint8_t *bytes, size_t size, unsigned count) {
        if (!count || count>lanes.size()) return false;
        for(auto &v:lanes) v.clear();
        while(size>=8) {
            float time=read<float>(bytes);
            uint32_t n=read<uint32_t>(bytes+4);
            bytes+=8; size-=8;
            if(std::isinf(time) && time>0 && !n && !size) {
                for(unsigned i=0;i<count;++i) if(lanes[i].empty()) return false;
                return true;
            }
            if(!std::isfinite(time) || n>count || n>size/20) return false;
            for(unsigned i=0;i<n;++i,bytes+=20,size-=20) {
                auto lane=read<uint32_t>(bytes);
                if(lane>=count || (!lanes[lane].empty() && time<=lanes[lane].back().time)) return false;
                lanes[lane].push_back({time,read<float>(bytes+4),read<float>(bytes+8),read<float>(bytes+12),read<float>(bytes+16)});
            }
        }
        return false;
    }
    float sample(unsigned lane, double t) const {
        const auto &v=lanes[lane];
        auto next=std::upper_bound(v.begin(),v.end(),t,[](double x,const Key &k){return x<k.time;});
        if(next==v.begin()) return v.front().d;
        auto &k=*(next-1);
        if(next==v.end() || k.time < -1.e30f) return k.d;
        double dt=t-k.time;
        return ((k.a*dt+k.b)*dt+k.c)*dt+k.d;
    }
};
}
