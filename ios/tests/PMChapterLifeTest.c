#include "../PhiMod/Core/PMChapterVM.h"
#include "../PhiMod/Core/PMChapterLife.inc"
#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct { int ceiling, choice, commits, reject; } Store;
static PMOSPage page;
static int readFlag(void *ctx, const char *key, int *value) {
    Store *s = ctx;
    *value = !strcmp(key, PMChapterLifeCeilingKey) ? s->ceiling :
             !strcmp(key, PMChapterLifeChoiceKey) ? s->choice : 0;
    return 1;
}
static int commit(void *ctx, const PMOSProgressChange *changes, size_t count) {
    Store *s = ctx;
    assert(count == 1 && !strcmp(changes[0].key, PMChapterLifeChoiceKey));
    if (s->reject) return 0;
    ++s->commits;
    s->choice = changes[0].value;
    return 1;
}
static int run(Store *store, const char *script) {
    PMOSProgress callbacks = {store, readFlag, commit};
    PMOSSession *s = PMOSStartWithProgress(script, strlen(script), 3, &page, callbacks);
    if (!s) return 0;
    PMOSStop(s);
    return 1;
}
static void testOutcomes(void) {
    for (int ceiling = 1; ceiling <= 4; ++ceiling) {
        for (int choice = 0; choice <= ceiling; ++choice) {
            for (int tier = 0; tier <= ceiling; ++tier) {
                PMChapterLifeState s = PMChapterLifeRead(ceiling, choice + 1);
                int promoted = tier == ceiling && ceiling < 4;
                assert(PMChapterLifeApplyOutcome(&s, tier, 0) == promoted);
                assert(s.ceiling == ceiling + promoted && s.selected == (promoted ? s.ceiling : choice));
                s = PMChapterLifeRead(ceiling, choice + 1);
                int next = tier <= 2 ? 1 : tier - 1;
                assert(PMChapterLifeApplyOutcome(&s, tier, 1) == (ceiling != next));
                assert(s.ceiling == next && s.selected == (choice > next ? next : choice));
            }
        }
    }
    PMChapterLifeState s = PMChapterLifeRead(0, 0);
    assert(!PMChapterLifeApplyOutcome(&s, -1, 0) && !PMChapterLifeApplyOutcome(&s, 5, 1));
    assert(s.ceiling == 1 && s.selected == 1);
}
int main(void) {
    testOutcomes();
    Store s = {0}, other = {0};
    const char *fresh = "local l=chapterLife(); if l.ceiling~=1 or l.selected~=1 or l.hp~=10 then invalid() end";
    assert(run(&s, fresh) && !s.commits);
    assert(run(&s, "chapterLife(0); if chapterLife().hp~=1 then invalid() end") && s.choice == 1 && s.commits == 1);
    assert(run(&s, "if chapterLife().selected~=0 then invalid() end") && s.commits == 1);
    assert(run(&other, fresh) && !other.commits);
    assert(!run(&s, "chapterLife(1); chapterLife(2)") && s.choice == 1 && s.commits == 1);
    assert(!run(&s, "chapterLife(-1)") && !run(&s, "chapterLife('1')") && !run(&s, "chapterLife(0,1)"));
    s.reject = 1;
    assert(!run(&s, "chapterLife(1)") && s.choice == 1);
    s.reject = 0;
    PMChapterLifeState result = PMChapterLifeRead(s.ceiling, s.choice);
    assert(PMChapterLifeApplyOutcome(&result, 1, 0));
    s.ceiling = result.ceiling; s.choice = result.selected + 1; /* Native outcome storage contract. */
    assert(run(&s, "local l=chapterLife(); if l.ceiling~=2 or l.hp~=50 then invalid() end;"
                   "challenge{id='gate',lifeTier=l.selected,secretCourse={{song=1},{song=2},{song=3}}}"));
    assert(page.challengeCount == 1 && page.challenges[0].lifeTier == 2);
    puts("chapter LIFE tests passed");
    return 0;
}
