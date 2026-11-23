#pragma once
#include <string.h>

typedef struct {
    const char *reference, *resource, *sha256;
    unsigned long long size, offset, resourceSize;
} PMStockIntro;

/* Verified serialized VideoClip resource spans, 4.0.4 build 3. */
static inline const PMStockIntro *PMStockIntroForName(const char *name) {
    static const PMStockIntro clips[] = {
        {"@stock/c8/321-unlock", "sharedassets24.resource",
         "190c4afffdfe7e3e9dc590641ade998001e6cea8e50d94bdd62d00e6de07cad6", 17776256, 0, 17776256},
        {"@stock/c8/qd-unlock", "sharedassets26.resource",
         "892af2348b28e338a206c7941bc5b7827a6489b33e3cf6e9f1ef1f9d8282c843", 16502874, 1769984, 18272858},
        {"@stock/c8/df-touch-to-start", "sharedassets27.resource",
         "069e825e8f2bab341f70776afc358eb94f2bdbc27871116cf588b5dd46719c68", 1044959, 0, 28957443},
        {"@stock/c8/df-unlock", "sharedassets27.resource",
         "3afc684ca21b9856c7dc140c118f1508ac0ce7c904ccca3f0defc0981ffbbac7", 27912484, 1044959, 28957443},
        {"@stock/c9/to-phase-2", "sharedassets31.resource",
         "db15104d7df695c5bc5070eb516de5a15e9f9d2ff29016f2e42e8828756cf756", 22781044, 0, 22781044},
        {"@stock/c9/ds-intro", "sharedassets33.resource",
         "9fbcd3c7f7f23a1dc2a3c079bc353c94aca3825ac00ba857d4c977f57d11939d", 11580169, 0, 59034216},
        {"@stock/c9/ds-at", "sharedassets33.resource",
         "36f29a0e5c67591c87fe6a100425c6cae597d9f97df46b1632ada15e209eef76", 11527396, 11580169, 59034216},
        {"@stock/c9/ds-in", "sharedassets33.resource",
         "3802c1443f1a929d6d91d7ff2be105d0fe2a86e8396d367471940294cca93cfe", 11543784, 23107565, 59034216},
        {"@stock/c9/ds-difficulties", "sharedassets33.resource",
         "814ccc6c4b47237f393901c6156038dade25837aacd7464dc0bea29f567bcc19", 612739, 34651349, 59034216},
        {"@stock/c9/ds-hd", "sharedassets33.resource",
         "caa5b7ade127d352e238c8e6e5da270cfff169930ef46aaa795fd64b4eac3249", 11948061, 35264088, 59034216},
        {"@stock/c9/ds-ez", "sharedassets33.resource",
         "f19d722b5630a016f9491d00d3f39c352b85f68cbe993b872af0880b91fe3dc3", 11822067, 47212149, 59034216},
        {"@stock/c9/after-deduction", "sharedassets37.resource",
         "13728576afb9e09b8a80bd3672440ed63fea46d02b2a466120de9f7e23de3fe2", 87770263, 0, 87770263},
    };
    for (size_t i = 0; name && i < sizeof(clips) / sizeof(clips[0]); ++i)
        if (!strcmp(name, clips[i].reference)) return &clips[i];
    return NULL;
}
