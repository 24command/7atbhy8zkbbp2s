#import "PMNativeOSProgram.h"
#import "PMChapterArt.h"
#import "PMChapterEditing.h"
#include "PMContentRuntime.hpp"
#import "PMChapterScript.h"
#import "PMContentStore.h"
#import "PMDoorRun.h"
#import "PMOSAuthorProgress.h"
#import "PMStockIntroResolver.hpp"
#import "PMStoryCueRun.h"
#import <UIKit/UIGeometry.h>
#include <memory>
#include <utility>

static int readStoryFlag(void *context, const char *key, int *value) {
    PMOSAuthorProgress *progress = (__bridge PMOSAuthorProgress *)context;
    return [progress readKey:[NSString stringWithUTF8String:key] value:value];
}
static int commitStoryFlags(void *context, const PMOSProgressChange *changes, size_t count) {
    PMOSAuthorProgress *progress = (__bridge PMOSAuthorProgress *)context;
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:count];
    for (size_t i = 0; i < count; ++i)
        values[[NSString stringWithUTF8String:changes[i].key]] = @(changes[i].value);
    return [progress commitValues:values];
}

// Older VM pages predate the explicit native chapter declaration.
template <class Page> static auto nativeChapterFlag(const Page &page, int) -> decltype(page.nativeChapter) {
    return page.nativeChapter;
}
template <class Page> static int nativeChapterFlag(const Page &, long) { return 9; }

// Lua declarations may read or commit author progress, which requires a background queue.
@interface PMNativeOSProgram ()
- (nullable instancetype)initWithChapter:(NSString *)chapter error:(NSError **)error;
@end

@implementation PMNativeOSProgram {
    PMOSAuthorProgress *_progress;
    PMOSSession *_session;
    std::unique_ptr<const PMOSPage> _plan;
    dispatch_queue_t _events;
    NSArray<NSDictionary *> *_unlockFields;
}

+ (void)loadChapter:(NSString *)chapter completion:(PMNativeOSLoadCompletion)completion {
    NSString *identifier = [chapter copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @autoreleasepool {
          NSError *error = nil;
          PMNativeOSProgram *program = [[self alloc] initWithChapter:identifier error:&error];
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(program, error);
          });
      }
    });
}

- (instancetype)initWithChapter:(NSString *)chapter error:(NSError **)error {
    if (!(self = [super init]))
        return nil;
    auto fail = [&](NSString *message) -> PMNativeOSProgram * {
        *error = [NSError errorWithDomain:@"PhiMod.ChapterOS"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
        return nil;
    };
    if (NSThread.isMainThread)
        return fail(@"Chapter OS loading requires a background queue");
    PMContentStore *store = PMContentStore.shared;
    if (!chapter.length || ![store hasChapterScript:chapter])
        return fail(@"Chapter script unavailable");
    PMDoorProgressBarrier();
    NSString *file = [[store asset:chapter] stringByAppendingPathComponent:PMChapterScriptName];
    NSData *source = PMChapterScriptData([NSURL fileURLWithPath:file], error);
    if (!source)
        return nil;
    NSDictionary *db = [store snapshot];
    NSArray *order = PMChapterSongIDs(db, nil, chapter);
    _progress = [[PMOSAuthorProgress alloc] initWithRoot:store.root chapter:chapter];
    if (!_progress)
        return fail(@"Chapter progress unavailable");
    _events = dispatch_queue_create("PhiMod.ChapterOS.events", DISPATCH_QUEUE_SERIAL);
    auto plan = std::make_unique<PMOSPage>();
    PMOSProgress callbacks = {(__bridge void *)_progress, readStoryFlag, commitStoryFlags};
    _session = PMOSStartWithProgress((const char *)source.bytes, source.length, (int)order.count, plan.get(),
                                     callbacks);
    if (!_session)
        return fail([NSString stringWithUTF8String:plan->error] ?: @"Invalid chapter script");
    NSMutableArray<NSString *> *screens = [NSMutableArray arrayWithCapacity:plan->screens];
    for (int i = 0; i < plan->screens; ++i) {
        NSString *name = [NSString stringWithUTF8String:plan->names[i]];
        if (!name) {
            return fail(@"Invalid UTF-8 page name");
        }
        [screens addObject:name];
    }
    NSMutableDictionary *songs = [NSMutableDictionary dictionary];
    for (NSDictionary *song in db[@"songs"])
        songs[song[@"id"]] = song;
    NSString *name = chapter;
    for (NSDictionary *c in db[@"chapters"])
        if ([c[@"id"] isEqual:chapter]) {
            name = c[@"name"];
            break;
        }
    NSMutableDictionary *bySong = [NSMutableDictionary dictionary];
    for (NSString *sid in order) {
        NSDictionary *song = songs[sid];
        NSMutableDictionary *row = [@{
            @"installedID" : sid,
            @"title" : song[@"title"] ?: sid,
            @"group" : [song[@"groupId"] length] ? song[@"groupId"] : sid,
            @"caption" : song[@"composer"] ?: @""
        } mutableCopy];
        if (song && ![song[@"unlock"][@"enabled"] boolValue])
            row[@"art"] = [[store asset:sid] stringByAppendingPathComponent:@"image.png"];
        bySong[sid] = [row copy];
    }
    NSMutableArray *cards = [NSMutableArray array];
    NSMutableSet *overridden = [NSMutableSet set];
    for (NSUInteger i = 0, n = plan->count ? (NSUInteger)plan->count : order.count; i < n; i++) {
        const PMOSCard *c = plan->count ? &plan->cards[i] : nullptr;
        if (!c && !PMOSSongVisible(_session, (int)i + 1)) continue;
        NSString *sid = order[c ? c->song - 1 : i];
        NSMutableDictionary *row = [bySong[sid] mutableCopy];
        if (c && c->title[0])
            row[@"title"] = [NSString stringWithUTF8String:c->title] ?: sid;
        if (c && c->caption[0])
            row[@"caption"] = [NSString stringWithUTF8String:c->caption] ?: @"";
        if (c && c->speech) {
            if (c->waveformCount)
                row[@"waveform"] = [NSData dataWithBytes:c->waveform length:c->waveformCount * sizeof(float)];
            row[@"seconds"] = @(c->seconds);
            row[@"speechHeading"] =
                (c->speechHeading[0] ? [NSString stringWithUTF8String:c->speechHeading] : nil)
                    ?: @"SPEECH_TO_TEXT";
        }
        [cards addObject:[row copy]];
    }
    for (int i = 0; i < plan->count; i++) {
        NSString *sid = order[plan->cards[i].song - 1];
        // A suppressed challenge card must not supply the title/artwork of another visible card.
        if (plan->cards[i].songSuppressed && PMOSSongVisible(_session, plan->cards[i].song)) continue;
        if (![overridden containsObject:sid]) {
            bySong[sid] = cards[i];
            [overridden addObject:sid];
        }
    }
    NSString *chapterDir = file.stringByDeletingLastPathComponent;
    NSMutableArray *challengeRows = [NSMutableArray arrayWithCapacity:plan->challengeCount];
    for (int i = 0; i < plan->challengeCount; i++) {
        const PMOSChallenge &challenge = plan->challenges[i];
        if (challenge.songSuppressed) {
            [challengeRows addObject:@{}]; // Keep the one-based challenge binding stable.
            continue;
        }
        const PMOSChallengeTier *tier = &challenge.tiers[0];
        for (int j = 1; j < challenge.tierCount && challenge.tiers[j].after <= challenge.failures; ++j)
            tier = &challenge.tiers[j];
        NSString *sid = order[challenge.song - 1];
        NSMutableDictionary *row = [bySong[sid] mutableCopy];
        row[@"challengeID"] = [NSString stringWithUTF8String:challenge.id];
        row[@"sid"] = sid;
        if (challenge.courseCount) {
            NSMutableArray *members = [NSMutableArray arrayWithCapacity:challenge.courseCount];
            for (int j = 0; j < challenge.courseCount; ++j) {
                const auto &member = challenge.course[j];
                NSMutableDictionary *m = [@{@"songID" : order[member.song - 1]} mutableCopy];
                if (member.difficulty[0])
                    m[@"difficulty"] = [NSString stringWithUTF8String:member.difficulty];
                [members addObject:[m copy]];
            }
            row[@"secretCourse"] = [members copy];
            row[@"lifeTier"] = @(challenge.lifeTier);
        } else {
            row[@"hp"] = @(tier->hp);
            row[@"delta"] = @[ @(tier->perfect), @(tier->good), @(tier->bad), @(tier->miss) ];
        }
        if (challenge.difficulty[0])
            row[@"difficulty"] = [NSString stringWithUTF8String:challenge.difficulty];
        row[@"noPause"] = @(challenge.noPause != 0);
        row[@"mapDetail"] = @(challenge.replayCount > 0);
        if (challenge.state == PMOSChallengeClear && challenge.replayCount) {
            NSMutableArray *entries = [NSMutableArray arrayWithCapacity:challenge.replayCount];
            for (int j = 0; j < challenge.replayCount; ++j) {
                const auto &option = challenge.replaySongs[j];
                NSString *idValue = order[option.song - 1];
                NSString *label =
                    option.difficulty[0] ? [NSString stringWithUTF8String:option.difficulty] : nil;
                NSString *title = bySong[idValue][@"title"] ?: idValue;
                NSMutableDictionary *entry = [@{
                    @"songID" : idValue,
                    @"title" : label ? [NSString stringWithFormat:@"%@ · %@", title, label] : title
                } mutableCopy];
                if (label)
                    entry[@"difficulty"] = label;
                if (bySong[idValue][@"art"])
                    entry[@"art"] = bySong[idValue][@"art"];
                [entries addObject:[entry copy]];
            }
            row[@"replaySongs"] = [entries copy];
        }
        row[@"showDetail"] = @(challenge.showDetail != 0);
        NSMutableArray *intro = [NSMutableArray array];
        for (int j = 0; j < challenge.introCount; j++) {
            NSString *name = [NSString stringWithUTF8String:challenge.intro[j]];
            NSString *path =
                [name hasPrefix:@"@stock/"] ? PMResolveStockIntro(name) : PMOSArtPath(chapterDir, name);
            if (!path || ![[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType]
                             isEqual:NSFileTypeRegular]) {
                return fail([NSString stringWithFormat:@"Missing chapter intro: %@", name]);
            }
            [intro addObject:path];
        }
        row[@"intro"] = [intro copy];
        NSMutableArray *nextSongs = [NSMutableArray array];
        for (int j = 0; j < challenge.nextSongCount; j++) {
            const PMOSChallengeSong &next = challenge.nextSongs[j];
            NSMutableDictionary *entry = [@{@"songID" : order[next.song - 1]} mutableCopy];
            if (next.difficulty[0])
                entry[@"difficulty"] = [NSString stringWithUTF8String:next.difficulty];
            [nextSongs addObject:[entry copy]];
        }
        row[@"nextSongs"] = [nextSongs copy];
        if (challenge.cueCount) {
            NSMutableArray *cues = [NSMutableArray arrayWithCapacity:challenge.cueCount];
            for (int j = 0; j < challenge.cueCount; j++) {
                const auto &cue = plan->cues[challenge.cueStart + j];
                [cues addObject:@{
                    @"at" : @(cue.at),
                    @"duration" : @(cue.duration),
                    @"blockPause" : @(cue.blockPause != 0),
                    @"text" : [NSString stringWithUTF8String:cue.text] ?: @"",
                    @"src" : [NSString stringWithUTF8String:cue.src] ?: @""
                }];
            }
            row[@"cues"] = PMStoryCuePrepare(cues, chapterDir);
        }
        [challengeRows addObject:[row copy]];
    }
    NSMutableIndexSet *suppressedCards = [NSMutableIndexSet indexSet];
    for (int i = 0; i < plan->count; i++) {
        if (plan->cards[i].songSuppressed) {
            [suppressedCards addIndex:(NSUInteger)i];
            continue;
        }
        int binding = plan->cards[i].challenge;
        if (binding <= 0)
            continue;
        NSMutableDictionary *card = [cards[i] mutableCopy];
        if (plan->challenges[binding - 1].state == PMOSChallengeLocked)
            card[@"lockedChallenge"] = @YES;
        else {
            NSDictionary *target = challengeRows[binding - 1];
            NSMutableDictionary *detail = [target mutableCopy];
            if (plan->cards[i].song == plan->challenges[binding - 1].song) {
                // A second card for the same song can omit the first card's waveform.
                detail[@"waveform"] = card[@"waveform"];
                for (NSString *key in @[ @"title", @"caption", @"speechHeading", @"seconds" ])
                    if (card[key])
                        detail[key] = card[key];
            }
            card[@"challengeDetail"] = [detail copy];
        }
        cards[i] = [card copy];
    }
    [cards removeObjectsAtIndexes:suppressedCards];
    NSMutableArray *nodes = [NSMutableArray new];
    for (int i = 0; i < plan->nodes; i++) {
        const PMOSNode &n = plan->elements[i];
        if (n.songSuppressed) {
            [nodes addObject:@{}]; // VM callbacks, parents and drag targets use declaration indices.
            continue;
        }
        NSMutableDictionary *model = [@{
            @"parent" : @(n.parent),
            @"screen" : @(n.screen),
            @"kind" : @(n.kind),
            @"dest" : @(n.dest),
            @"rect" : [NSValue valueWithCGRect:CGRectMake(n.x, n.y, n.w, n.h)],
            @"rgba" : @(n.rgba),
            @"fill" : @(n.fill),
            @"loop" : @(n.loop),
            @"handler" : @(n.handler != 0),
            @"hidden" : @(n.hidden),
            @"start" : @(n.start),
            @"duration" : @(n.duration),
            @"fade" : @(n.fade)
        } mutableCopy];
        if (n.id[0])
            model[@"id"] = [NSString stringWithUTF8String:n.id];
        if (n.challenge)
            model[@"challenge"] = @(n.challenge);
        if (n.label[0])
            model[@"label"] = [NSString stringWithUTF8String:n.label];
        if (n.to[0])
            model[@"to"] = [NSString stringWithUTF8String:n.to];
        if (n.open)
            model[@"song"] = bySong[order[n.open - 1]];
        if (n.dropIndex >= 0) {
            model[@"dropIndex"] = @(n.dropIndex);
            model[@"alphaHit"] = @(n.alphaHit != 0);
        }
        if (n.cover)
            model[@"path"] = bySong[order[n.cover - 1]][@"art"];
        if (n.src[0]) {
            NSString *path = PMOSArtPath(chapterDir, [NSString stringWithUTF8String:n.src]);
            if (!path || ![[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType]
                             isEqual:NSFileTypeRegular]) {
                return fail([NSString stringWithFormat:@"Missing or invalid image: %s", n.src]);
            }
            model[@"path"] = path;
        }
        [nodes addObject:[model copy]];
    }

    // Authored indexes can refer to official songs moved into this chapter, too.
    NSDictionary *retail = PMOfficialSongMap(pmcontent::cachedOfficialSnapshot());
    NSMutableArray *fields=[NSMutableArray arrayWithCapacity:order.count];
    for(NSString *sid in order){
        NSDictionary *chart=songs[sid], *stock=retail[sid];
        NSString *title=bySong[sid][@"title"];
        if(!title.length || [title isEqual:sid])title=chart[@"title"] ?: stock[@"songsName"] ?: sid;
        NSString *level=[chart[@"difficultyText"] description] ?: [chart[@"difficulty"] description];
        [fields addObject:@{@"title":title, @"artist":chart[@"composer"] ?: stock[@"composer"] ?: @"",
                            @"difficulty":chart[@"level"] ?: @"", @"level":level ?: @"",
                            @"charter":chart[@"charter"] ?: @"", @"illustrator":chart[@"illustrator"] ?: stock[@"illustrator"] ?: @""}];
    }
    _unlockFields=[fields copy];
    _chapter = [chapter copy];
    _chapterName = [name copy] ?: _chapter;
    _scriptHash = PMChapterScriptDigest(source);
    _screens = [screens copy];
    _order = [order copy];
    _bySong = [bySong copy];
    NSMutableDictionary *visible = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < order.count; ++i)
        if (PMOSSongVisible(_session, (int)i + 1)) visible[order[i]] = bySong[order[i]];
    _visibleBySong = [visible copy];
    _cards = [cards copy];
    _nodes = [nodes copy];
    _challengeRows = [challengeRows copy];
    _listSwitchHidden = plan->listSwitchHidden != 0;
    _listFirst = plan->listFirst != 0;
    _aspect = plan->aspect;
    _nativeChapter = nativeChapterFlag(*plan, 0);
    _selectedLifeTier = plan->selectedLifeTier;
    _plan = std::move(plan);
    return self;
}

- (const PMOSPage *)page {
    return _plan.get();
}

- (NSDictionary<NSString *,NSString *> *)unlockFieldsForSong:(NSInteger)song {
    return song>0 && (NSUInteger)song<=_unlockFields.count ? _unlockFields[song-1] : @{};
}
- (void)markUnlockSeen:(NSInteger)index completion:(void (^)(BOOL))completion {
    if(index<0 || index>=_plan->unlockAnimationCount){completion(NO);return;}
    NSString *key=@(_plan->unlockAnimations[index].progressKey);
    dispatch_async(_events, ^{
        BOOL ok=[self->_progress commitValues:@{key:@1}];
        dispatch_async(dispatch_get_main_queue(), ^{completion(ok);});
    });
}
- (void)markEntryMovieSeen:(void (^)(BOOL))completion {
    NSString *key = @(_plan->entryMovieKey);
    dispatch_async(_events, ^{
        BOOL ok = [self->_progress commitValues:@{key:@1}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
    });
}

- (void)clickNode:(NSInteger)index completion:(PMNativeOSClickCompletion)completion {
    dispatch_async(_events, ^{
      @autoreleasepool {
          PMOSAction action = {};
          int node = index >= 0 && index < (NSInteger)self.nodes.count ? (int)index : -1;
          BOOL ok = PMOSClick(self->_session, node, &action);
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(ok, &action);
          });
      }
    });
}

- (void)dealloc {
    // Each queued click retains self through its VM call. Keep the borrowed
    // progress context alive until the serial queue has closed Lua as well.
    PMOSSession *session = _session;
    PMOSAuthorProgress *progress = _progress;
    if (session)
        dispatch_async(_events, ^{
          PMOSStop(session);
          (void)progress;
        });
}
@end
