#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Transparent stock-art overlay for a UIKit host (including one with an AVPlayerLayer).
// Main-thread entry points. Completion runs asynchronously on main with nil on failure.
// The coordinator owns the clock, media, visit lifetime and removal. Check the current
// visit in completion before attaching a view prepared for an earlier request.
@interface PMStockUnlockInfoView : UIView
@property(nonatomic, readonly, copy) NSString *songID;
// chapter: 5, 6, 7 or 0 (shared challenge ShowInfoETC). All fields refer to this exact
// song row: title (required), artist, difficulty, level, charter, illustrator (strings).
// Show is the start of the native alpha ramp, hide is the end of the fade-out. Supply
// -1 for clip defaults. Custom windows may extend past the retail movie for custom src.
+ (void)prepareChapter:(NSInteger)chapter songID:(NSString *)songID
                fields:(NSDictionary<NSString *,NSString *> *)fields
       infoShowSeconds:(double)show infoHideSeconds:(double)hide
            completion:(void (^)(PMStockUnlockInfoView * _Nullable view))completion;
// Drive with absolute media seconds. Supports pause, stall and seek in either direction.
- (void)setPresentationSeconds:(double)seconds;
// For the coordinator's stock movie resolver. Generic has no chapter movie.
+ (nullable NSString *)stockMovieReferenceForChapter:(NSInteger)chapter;
@end
NS_ASSUME_NONNULL_END
