#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {int song,speech; double seconds;char speechHeading[192];char title[256], caption[1024];} PMOSCard;
enum {PMOSFrame, PMOSImage, PMOSHotspot};
enum { PMOSMaxNodes = 256, PMOSMaxScreens = 32, PMOSScreenNameSize = 64 };
typedef struct {double x,y,w,h,start,duration,fade;int kind,parent,depth,cover,open,screen,dest,fill,loop,handler,hidden;unsigned rgba;char id[64],src[256],label[256],to[64];} PMOSNode;
enum { PMOSProgressKeyMax = 64, PMOSProgressAccessLimit = 128 };
enum { PMOSMaxChallenges = 32, PMOSMaxChallengeTiers = 16,
       PMOSChallengeIdMax = PMOSProgressKeyMax - (sizeof("door..clear") - 1) };
typedef enum { PMOSChallengeLocked, PMOSChallengeClosed, PMOSChallengeClear } PMOSChallengeState;
typedef struct {
    int after;
    float hp, perfect, good, bad, miss;
} PMOSChallengeTier;
typedef struct {
    char id[PMOSChallengeIdMax + 1], difficulty[96]; /* Empty difficulty if omitted. */
    int song, failures, tierCount;
    PMOSChallengeState state;
    PMOSChallengeTier tiers[PMOSMaxChallengeTiers]; /* Increasing after, starting at zero. */
} PMOSChallenge;
typedef struct {int nodes,screens;double aspect;char names[PMOSMaxScreens][PMOSScreenNameSize];PMOSNode elements[PMOSMaxNodes];int listFirst,count; PMOSCard cards[128];char error[384];
    int challengeCount; PMOSChallenge challenges[PMOSMaxChallenges];
} PMOSPage;
typedef struct PMOSSession PMOSSession;
typedef struct {int song, dest, element, visible; char error[384]; int checkpoint; char difficulty[96]; int challenge;} PMOSAction;

typedef struct { char key[PMOSProgressKeyMax + 1]; int value; } PMOSProgressChange;
typedef struct {
    void *context;
    int (*read)(void *context, const char *key, int *value);
    int (*commit)(void *context, const PMOSProgressChange *changes, size_t count);
} PMOSProgress;

/* Each load/click allows up to PMOSProgressAccessLimit combined gets/sets.
   Keys are 1..64 ASCII bytes from [A-Za-z0-9_.-]. Values are Lua integers
   representable as C int. Reads see staged writes. Repeated sets coalesce.
   read returns 1 on success (value = 0 for a missing key). If read is NULL,
   unstaged keys read as zero. set requires a commit callback.
   After validation, commit receives one nonempty batch. It must atomically
   apply all changes and return 1, or leave storage unchanged and return 0.
   Only stored progress is transactional. Lua closure state survives failed clicks.
   Callbacks are synchronous. Their key/batch arguments are borrowed for the call.
   Keep context valid until stop and do not reenter the session from callbacks. */
PMOSSession *PMOSStartWithProgress(const char *source, size_t len, int songs,
                                  PMOSPage *page, PMOSProgress callbacks);

/* The caller owns the source and page and may release both after start returns.
   Serialize clicks and stop for a given session. A failed start sets page->error. */
PMOSSession *PMOSStart(const char *source, size_t len, int songs, PMOSPage *page);
void PMOSStop(PMOSSession *session);
/* Pass the zero-based element index (handler is a presence flag). Static actions
   are supported too. song defaults to 0, dest and element to -1. For show/hide,
   element indexes page->elements on the clicked screen and visible is 1/0.
   checkpoint is 0 for ordinary actions, 1 for session, or 2 for relaunch.
   Checkpoints use dest for a page or song with an optional difficulty (empty if omitted).
   challenge is a 1-based index into page->challenges, or 0 when absent. A locked
   challenge returns a successful empty action. Cleared challenges can be replayed.
   Failure returns 0, clears the action and sets out->error. */
int PMOSClick(PMOSSession *session, int zeroBasedNode, PMOSAction *out);
int PMBuildOSPage(const char *source,size_t len,int songs,PMOSPage *page);
#ifdef __cplusplus
}
#endif
