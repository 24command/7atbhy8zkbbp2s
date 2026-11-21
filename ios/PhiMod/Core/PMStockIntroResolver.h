#pragma once
#include <string.h>

typedef struct {
    const char *reference, *resource, *sha256;
    unsigned long long size;
} PMStockIntro;

/* 4.0.4 build 3. Each serialized VideoClip covers its entire resource from
   offset zero. Multi-clip resources and Addressables keys are excluded. */
static inline const PMStockIntro *PMStockIntroForName(const char *name) {
    static const PMStockIntro clips[] = {
        {"@stock/c8/321-unlock", "sharedassets24.resource",
         "190c4afffdfe7e3e9dc590641ade998001e6cea8e50d94bdd62d00e6de07cad6", 17776256},
        {"@stock/c9/to-phase-2", "sharedassets31.resource",
         "db15104d7df695c5bc5070eb516de5a15e9f9d2ff29016f2e42e8828756cf756", 22781044},
        {"@stock/c9/after-deduction", "sharedassets37.resource",
         "13728576afb9e09b8a80bd3672440ed63fea46d02b2a466120de9f7e23de3fe2", 87770263},
    };
    for (size_t i = 0; name && i < sizeof(clips) / sizeof(clips[0]); ++i)
        if (!strcmp(name, clips[i].reference)) return &clips[i];
    return NULL;
}
