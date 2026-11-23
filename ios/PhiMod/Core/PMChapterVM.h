#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* On cards and nodes, challenge is 0 when unbound, otherwise a one-based index
   into page->challenges, including locked entries. A bound card keeps its song
   for presentation; activation uses the challenge and is inert when locked. */
typedef struct {int song,speech; double seconds;char speechHeading[192];char title[256], caption[1024];int challenge;
    /* Ordered C8 WaveDisplay bar heights in [0,1]. The 4.0.4 donor has 100 bars. */
    int waveformCount;
    float waveform[100];
    int songSuppressed;
} PMOSCard;
enum {PMOSFrame, PMOSImage, PMOSHotspot};
enum { PMOSMaxNodes = 256, PMOSMaxScreens = 32, PMOSScreenNameSize = 64 };
/* Optional layout motion. Times use the screen clock. bob is measured in node
   heights. tapScale is the peak multiplier and tapFlash the peak white opacity.
   A click uses the closest tapTime-bearing frame/node in its ancestry. */
typedef struct { double enter, bob, bobPeriod, tapTime, tapScale, tapFlash; } PMOSMotion;
typedef struct {double x,y,w,h,start,duration,fade;int kind,parent,depth,cover,open,screen,dest,fill,loop,handler,hidden;unsigned rgba;char id[64],src[256],label[256],to[64];int challenge; char dropTarget[64]; int dropIndex, alphaHit;
    PMOSMotion motion;
    char tapFace[64]; /* Optional descendant ID. Empty flashes the whole node. */
    int tapFaceIndex;
    int songSuppressed; /* Permanent for this declaration, including inherited suppression. */
} PMOSNode;
enum { PMOSProgressKeyMax = 64, PMOSProgressAccessLimit = 128 };
enum { PMOSMaxChallenges = 32, PMOSMaxChallengeTiers = 16,
       PMOSChallengeIdMax = PMOSProgressKeyMax - (sizeof("door..clear") - 1) };
typedef enum { PMOSChallengeLocked, PMOSChallengeClosed, PMOSChallengeClear } PMOSChallengeState;
typedef struct {
    int after;
    float hp, perfect, good, bad, miss;
} PMOSChallengeTier;
/* Lua challenge.cues is optional. Supply a dense 1-based array of dictionaries.
   at >= 0, duration > 0 and their sum must be finite gameplay seconds. Each cue
   needs text, src or blockPause=true. Strings are 1..255 bytes without NUL.
   src is a local PNG/JPG/JPEG/WebP filename. Omitted strings are empty and
   blockPause defaults to false. The page accepts up to 128 cues total, in
   declaration and array order. Exceeding that limit rejects the page. */
enum { PMOSMaxChallengeCues = 128 };
typedef struct {
    double at, duration; /* Seconds on the gameplay clock. */
    char text[256], src[256];
    int blockPause;
} PMOSChallengeCue;
enum { PMOSMaxChallengeIntro = 4, PMOSMaxChallengeNextSongs = 2, PMOSMaxChallengeReplays = 8 };
typedef struct { int song; char difficulty[96]; } PMOSChallengeSong;
typedef struct {
    char id[PMOSChallengeIdMax + 1], difficulty[96]; /* Empty difficulty if omitted. */
    int song, failures, tierCount;
    PMOSChallengeState state;
    PMOSChallengeTier tiers[PMOSMaxChallengeTiers]; /* Increasing after, starting at zero. */
    int courseCount, lifeTier; /* 3 visible songs, optional fourth; -1 follows the current chapter-local tier. */
    PMOSChallengeSong course[4];
    int noPause, replayCount;
    PMOSChallengeSong replaySongs[PMOSMaxChallengeReplays];
    int cueStart, cueCount;
    int introCount, showDetail, nextSongCount; /* showDetail defaults to 1. Zero starts play after intro. */
    char intro[PMOSMaxChallengeIntro][256]; /* Local GIF/MP4 basenames in playback order. */
    PMOSChallengeSong nextSongs[PMOSMaxChallengeNextSongs]; /* After each clear, in order. */
    int songSuppressed;
} PMOSChallenge;
enum { PMOSMaxUnlockAnimations = 32,
       PMOSUnlockIdMax = PMOSProgressKeyMax - (sizeof("unlock.") - 1) };
typedef enum { PMOSUnlockMod, PMOSUnlockC5, PMOSUnlockC6, PMOSUnlockC7,
               PMOSUnlockC8, PMOSUnlockC9 } PMOSUnlockStyle;
typedef enum { PMOSUnlockEnter, PMOSUnlockEvent } PMOSUnlockWhen;
/* unlockAnimation{...} requires a unique progress-safe id, a one-based song and
   a style. src is a UTF-8 local MP4 basename or a known @stock clip, required
   for mod. All supplied times are seconds in [0,86400]. after delays playback.
   Each omitted info bound is -1 so the presenter resolves the clip/style default.
   A supplied bound has its presence flag set, including an explicit zero.
   When both are supplied, infoUntil must follow infoAt. An explicit duration
   must be positive and contain the supplied bounds (infoAt < duration). */
typedef struct {
    char id[PMOSUnlockIdMax + 1], progressKey[PMOSProgressKeyMax + 1], src[256];
    int song, once, seen;
    PMOSUnlockStyle style;
    PMOSUnlockWhen when;
    double after, infoAt, infoUntil, duration; /* 0 duration = automatic. */
    int hasInfoAt, hasInfoUntil;
} PMOSUnlockAnimation;
typedef struct {int nodes,screens;double aspect;char names[PMOSMaxScreens][PMOSScreenNameSize];PMOSNode elements[PMOSMaxNodes];int listFirst,count,listSwitchHidden,selectedLifeTier; int nativeChapter; /* 8 or 9, defaults to 9. */ PMOSCard cards[128];char error[384];
    int cueCount; PMOSChallengeCue cues[PMOSMaxChallengeCues];
    int challengeCount; PMOSChallenge challenges[PMOSMaxChallenges];
    char entryMovieKey[65],entryMovieName[256]; int entryMovieSeen;
    char chapterCover[256]; /* Last chapterCover(stillBasename) during declaration; empty = configured art. */
    int nativePhase; /* 1 by default, or 2 for nativeChapter(9, 2). */
    /* Scan in declaration order for when == PMOSUnlockEnter && !seen. seen is
       a load-time snapshot of once && progress.get(progressKey) != 0. */
    int unlockAnimationCount;
    PMOSUnlockAnimation unlockAnimations[PMOSMaxUnlockAnimations];
} PMOSPage;
typedef struct PMOSSession PMOSSession;
typedef struct {int song, dest, element, visible; char error[384]; int checkpoint; char difficulty[96]; int challenge;
    /* A nonempty revealTitle tags a focus/popup. element is its resolved local
       target and song is the optional one-based native song (0 to resume only). */
    char revealTitle[256], revealText[1024];
    int listSwitchHidden,selectedLifeTier;
    /* One-based page index for an event scene. 0 also represents a suppressed
       once event. Each click reads live/staged progress. The presenter writes
       unlock.<id> = 1 on completion for once scenes. The VM never marks them. */
    int unlockAnimation;
} PMOSAction;

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
/* Evaluate a declaration in isolation. Reads see staged writes, but the caller's
   commit callback is never invoked. An absent/invalid cover yields an empty name. */
int PMOSPreviewCover(const char *source, size_t len, int songs, PMOSProgress progress, char name[256]);
PMOSSession *PMOSStartWithProgress(const char *source, size_t len, int songs,
                                  PMOSPage *page, PMOSProgress callbacks);

/* The caller owns the source and page and may release both after start returns.
   Serialize clicks and stop for a given session. A failed start sets page->error. */
PMOSSession *PMOSStart(const char *source, size_t len, int songs, PMOSPage *page);
void PMOSStop(PMOSSession *session);
/* Lua songVisible(song, bool) is declaration-only. Songs start visible and the
   last declaration wins. This query returns false for invalid one-based indices. */
int PMOSSongVisible(const PMOSSession *session, int song);
/* Pass the zero-based element index (handler flags a Lua callback or a playable
   static challenge, both dispatched via PMOSClick). Static actions
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
