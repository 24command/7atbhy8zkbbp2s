#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
// Standalone OS audio. Never configures AVAudioSession or touches Unity audio.
@interface PMNativeOSAudio : NSObject
// Synchronous WORKER-only load; publish to main queue after completion. No play
// or prepareToPlay here (prepareToPlay implicitly activates the global session).
// At most 64 dictionaries; screen is a nonnegative NSNumber page index.
// src: basename in chapterDir/os-media (m4a/wav/mp3/aac/caf/aiff), AV-decodable.
// Optional introSrc: a distinct basename, only with page + loop=true. introSrc
// plays once, then src loops. Both must decode; either failure disables the cue.
// Their boundary is pre-scheduled on AV's device clock, independent of page ticks.
// event defaults page, channel defaults effect, start/duration=0, volume=1,
// loop=false. tap requires start=0 and loop=false; nil/empty target is wildcard.
// Duplicate screen/event/channel/start (page) or target (tap) is invalid.
// 32 MiB/file, 64 MiB total unique bytes. Invalid schema returns nil/error;
// missing/unsupported assets disable only their cues and appear in diagnostics.
// Host must treat nil/error as audio-only failure, never reject OS selection.
- (nullable instancetype)initWithCues:(NSArray<NSDictionary *> *)cues
                          chapterDir:(NSString *)chapterDir
                               error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly, copy) NSArray<NSError *> *diagnostics;
@property(nonatomic, readonly, nullable) NSError *lastPlaybackError;
// All methods/properties below are MAIN-thread-only. No audio before activation.
// time: effective elapsed seconds in this page visit, frozen by host while
// inactive/suspended/backgrounded. New page => new elapsed clock (usually zero).
// Repeating the same screen does nothing, even if time differs.
// start is page-relative; duration=0 means natural end (or indefinite loop).
// Late page cues seek by elapsed time; newer expired/failed cues silence the
// channel. Across pages only a currently due page BGM of the same src AND introSrc continues
// without seeking; new volume/loop apply, deadline is NEW page start+duration.
// A future/absent BGM stops the old one. Effects never carry across pages.
- (void)activateScreen:(NSInteger)screen time:(NSTimeInterval)time;
- (void)tickAt:(NSTimeInterval)time active:(BOOL)active;
// Call exactly for accepted input. IDs must be nonzero, strictly increasing over
// this object's lifetime; repeated/older IDs are ignored. node is exact node id.
// Per channel: specific target wins over wildcard, once per accepted tap.
- (void)tap:(uint64_t)acceptedTapID node:(nullable NSString *)node time:(NSTimeInterval)time;
// Cancels any scheduled intro/loop pair and saves the actual transport cursor.
// Resume schedules only remaining intro, or resumes loop without repeating intro.
- (void)setSuspended:(BOOL)suspended;
// Detail overlay: freeze page cue scheduling, keep current audio playing.
// Keep ticking with active:YES and the frozen page elapsed value. Tap cues are
// ignored while held. Existing effects may finish; no future page cues start.
// Return to map: set NO and continue the SAME elapsed clock; no reset or seek.
// Background/setSuspended:YES still physically pause audio, even while held.
// resetPlayback clears this hold. duration deadlines remain on the page clock.
- (void)setPageClockHeld:(BOOL)held;
// True while this runtime owns a BGM, including a paused BGM. Optional callback
// runs synchronously BEFORE first BGM play and AFTER final stop/failure. Main
// can mute/restore its own stock source here; runtime never does that itself.
// Install before activate. Callback must not reenter or retain this object.
// Host must call stop on main before releasing a live visit.
@property(nonatomic, readonly) BOOL ownsBGM;
@property(nonatomic, copy, nullable) void (^bgmOwnershipChanged)(BOOL ownsBGM);
// Reusable scene/page-visit reset: stops both channels and clears ownership,
// current screen/time and fired cues; cancels both intro/loop schedules;
// retains decoded assets/cues and tap IDs.
// Use when Program survives clearScene. For same-page reentry / elapsed rollback,
// call resetPlayback, then activateScreen:time:. No sound until activation.
- (void)resetPlayback;
// Terminal/idempotent: stops both channels, removes observers and releases data.
- (void)stop;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
