// Ported from the supplied Android native/rpe_text.h; semantics match Phira String::tween.
#pragma once
#include <string>
#include <vector>
#include <cmath>
#include <sstream>
#include <iomanip>
#include <algorithm>

inline std::vector<size_t> rpeCharEnds(const std::string& s) {
    std::vector<size_t> ends{0};
    for (size_t i = 0; i < s.size();) {
        unsigned char ch = s[i];
        size_t n = ch < 0x80 ? 1 : ch < 0xe0 ? 2 : ch < 0xf0 ? 3 : 4;
        i = std::min(s.size(), i + n);
        ends.push_back(i);
    }
    return ends;
}
inline std::string rpeTextWithoutMarker(std::string s) {
    size_t p;
    while ((p = s.find("%P%")) != std::string::npos)
        s.erase(p, 3);
    return s;
}
inline std::string rpeTextTween(const std::string& a, const std::string& b, float t) {
    t = std::clamp(t, 0.f, 1.f);
    if (a.find("%P%") != std::string::npos && b.find("%P%") != std::string::npos) {
        std::string x = rpeTextWithoutMarker(a), y = rpeTextWithoutMarker(b);
        if (t <= 0)
            return x;
        if (t >= 1)
            return y;
        float from = 0, to = 0;
        try {
            from = std::stof(x);
        } catch (...) {
        }
        try {
            to = std::stof(y);
        } catch (...) {
        }
        std::ostringstream s;
        s << std::fixed
          << std::setprecision(std::floor(from) == from && std::floor(to) == to ? 0 : 3)
          << from + (to - from) * t;
        return s.str();
    }
    if (a.empty() && b.empty())
        return "";
    if (b.empty())
        return rpeTextTween("", rpeTextWithoutMarker(a), 1 - t);
    auto aa = rpeCharEnds(a), bb = rpeCharEnds(b);
    size_t na = aa.size() - 1, nb = bb.size() - 1;
    if (a.empty()) {
        size_t n = std::min(nb, (size_t)std::round(t * nb));
        return b.substr(0, bb[n]);
    }
    if (b.rfind(a, 0) == 0) {
        size_t n = std::min(nb, na + (size_t)std::floor((nb - na) * t));
        return b.substr(0, bb[n]);
    }
    if (a.rfind(b, 0) == 0) {
        size_t n = std::min(na, nb + (size_t)std::round((na - nb) * (1 - t)));
        return a.substr(0, aa[n]);
    }
    return rpeTextWithoutMarker(a);
}
