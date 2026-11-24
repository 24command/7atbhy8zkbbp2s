#import "PMNativeOSActions.hpp"
#import "PMChapterArt.h"
#import "PMContentStore.h"
#import "PMOSCheckpoint.h"
#import "PMDiagnostics.h"
#import "PMOSRevealView.h"
#import "PMStockIntroResolver.hpp"
#import "PMUnlockMedia.h"
#import "PMUnlockRuntime.hpp"
#import "PMStockUnlockPresenter.h"
#include "PMStockUnlockLayout.hpp"
#import "PMChapterC8C9UnlockInfo.hpp"
#import <AVFoundation/AVFoundation.h>
#include <memory>

namespace {
constexpr NSUInteger cardsPerSheet = 6;
constexpr NSInteger previousSheet = -1, nextSheet = -2;

// The shared media presenter attaches to the foreground key window. Require an
// unambiguous game window for all three presentations, including on iPad.
UIWindow *gameWindow() {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return nil;
    UIWindow *result = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.isKeyWindow) continue;
            if (result || w.hidden || w.windowLevel != UIWindowLevelNormal || w.rootViewController.presentedViewController) return nil;
            result = w;
        }
    }
    return result;
}

// Match the native map's nested top-left normalized RectTransforms and FitInParent.
CGRect normalizedRect(const PMOSPage &page, NSInteger index) {
    CGRect r = CGRectMake(0, 0, 1, 1);
    for (NSInteger i = index; i >= 0;) {
        const auto &node = page.elements[i];
        r = CGRectMake(node.x + r.origin.x * node.w, node.y + r.origin.y * node.h,
                       r.size.width * node.w, r.size.height * node.h);
        if (node.parent >= i || node.parent < -1) return CGRectNull;
        i = node.parent;
    }
    return r;
}
CGRect focusRect(CGRect bounds, double aspect, CGRect rect) {
    CGSize s = bounds.size;
    if (aspect > 0) {
        s.width = MIN(s.width, s.height * aspect);
        s.height = s.width / aspect;
    }
    return CGRectMake(CGRectGetMidX(bounds) + (rect.origin.x - .5) * s.width,
                      CGRectGetMidY(bounds) + (rect.origin.y - .5) * s.height,
                      rect.size.width * s.width, rect.size.height * s.height);
}
}

@interface PMNativeFocusPanel : UIView
@property(nonatomic) CGRect sourceRect, targetRect;
@property(nonatomic) double aspect;
@property(nonatomic,strong) UIView *source, *target;
@end
@implementation PMNativeFocusPanel
- (void)layoutSubviews {
    [super layoutSubviews];
    self.source.frame = focusRect(self.bounds, self.aspect, self.sourceRect);
    self.target.frame = focusRect(self.bounds, self.aspect, self.targetRect);
    [self.subviews.lastObject setNeedsLayout];
}
@end

@implementation PMNativeOSActions {
    PMNativeOSProgram *_program;
    BOOL (^_current)(void);
    std::unique_ptr<PMOSPage> _sheet;
    NSArray<NSDictionary *> *_models;
    NSArray<NSNumber *> *_routes;
    NSUInteger _firstCard;
    UIView *_panel;
    PMOSRevealView *_reveal;
    id _resignObserver;
    BOOL _intro, _ownsMedia;
}
- (instancetype)initWithProgram:(PMNativeOSProgram *)program current:(BOOL (^)(void))current {
    if (!(self = [super init])) return nil;
    _program = program;
    _current = [current copy];
    bool hasMapNodes=false;
    for(int i=0;i<program.page->nodes;++i)
        if(program.page->elements[i].screen!=program.page->entryTransition.screen)hasMapNodes=true;
    if (!hasMapNodes) {
        _sheet = std::make_unique<PMOSPage>(*program.page);
        _sheet->screens = 1;
        _sheet->initialScreen=0;_sheet->entryTransition.screen=-1;
        strcpy(_sheet->names[0], "cards");
        [self buildSheet];
    }
    return self;
}
- (BOOL)cardOnly { return _sheet != nullptr; }
- (const PMOSPage *)page { return _sheet ? _sheet.get() : _program.page; }
- (NSArray<NSDictionary *> *)nodes { return _sheet ? _models : _program.nodes; }
- (BOOL)isCurrent { return NSThread.isMainThread && _current && _current(); }
- (BOOL)ready { return [self isCurrent] && !_panel && !_intro && !PMUnlockMediaBusy(); }

- (void)buildSheet {
    PMOSPage &page = *_sheet;
    page.nodes = 0;
    NSMutableArray *models = [NSMutableArray array], *routes = [NSMutableArray array];
    auto add = [&](NSInteger route, CGRect rect, NSString *title, NSDictionary *card, BOOL enabled) {
        PMOSNode &n = page.elements[page.nodes++];
        n = {};
        n.kind = PMOSFrame;
        n.screen = 0;
        n.dest = n.parent = n.dropIndex = -1;
        n.handler = enabled;
        n.x = rect.origin.x; n.y = rect.origin.y; n.w = rect.size.width; n.h = rect.size.height;
        n.rgba = enabled ? 0x273442ff : 0x313131ff;
        // getBytes returns a prefix ending on a code point boundary.
        NSUInteger bytes = 0;
        [title getBytes:n.label maxLength:sizeof(n.label)-1 usedLength:&bytes encoding:NSUTF8StringEncoding options:0
                  range:NSMakeRange(0, title.length) remainingRange:nullptr];
        n.label[bytes] = 0;
        NSMutableDictionary *model = [@{@"label":title, @"rect":[NSValue valueWithCGRect:rect],
                                         @"kind":@(n.kind), @"screen":@0, @"parent":@(-1), @"dest":@(-1),
                                         @"handler":@(enabled), @"rgba":@(n.rgba)} mutableCopy];
        NSString *art = card[@"art"];
        if (art && [[NSFileManager.defaultManager attributesOfItemAtPath:art error:nil][NSFileType] isEqual:NSFileTypeRegular]) model[@"path"] = art;
        if (card) model[@"card"] = card;
        [models addObject:[model copy]];
        [routes addObject:@(route)];
    };
    NSArray *cards = _program.cards;
    NSUInteger count = MIN(cardsPerSheet, cards.count - _firstCard);
    for (NSUInteger i = 0; i < count; ++i) {
        NSDictionary *card = cards[_firstCard + i];
        BOOL locked = [card[@"lockedChallenge"] boolValue];
        NSString *title = card[@"title"] ?: card[@"installedID"] ?: @"";
        add(_firstCard + i, CGRectMake(.06 + .30*(i%3), .16 + .29*(i/3), .28, .25),
            locked ? [@"🔒 " stringByAppendingString:title] : title, card, !locked);
    }
    if (_firstCard) add(previousSheet, CGRectMake(.15,.75,.25,.10), @"上一页", nil, YES);
    if (_firstCard + count < cards.count) add(nextSheet, CGRectMake(.60,.75,.25,.10), @"下一页", nil, YES);
    if (!count) add(0, CGRectMake(.25,.35,.5,.25), @"此章节没有曲目", nil, NO);
    _models = [models copy];
    _routes = [routes copy];
}
- (void)activateCardNode:(NSInteger)index open:(void (^)(NSDictionary *))open rebuild:(void (^)(void))rebuild {
    if (![self ready] || !_sheet || index < 0 || (NSUInteger)index >= _routes.count || !_sheet->elements[index].handler) return;
    NSInteger route = _routes[index].integerValue;
    if (route < 0) {
        if (route == nextSheet) _firstCard += cardsPerSheet; else _firstCard -= cardsPerSheet;
        [self buildSheet];
        rebuild();
        return;
    }
    NSDictionary *card = _program.cards[route];
    open(card[@"challengeDetail"] ?: card);
}

#include "PMNativeOSUnlockPlayback.inc"

- (BOOL)playEntryMovie:(void (^)(BOOL))completion {
    if (![self ready] || !gameWindow()) return NO;
    const PMOSPage *page = _program.page;
    if (!page->entryMovieKey[0] || page->entryMovieSeen) return NO;
    NSString *path = PMOSArtPath([PMContentStore.shared asset:_program.chapter], @(page->entryMovieName));
    if (!path || ![[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular]) {
        PMDiagnosticsWrite("Chapter OS: entry movie unavailable"); return NO;
    }
    __weak PMNativeOSActions *weak = self;
    _intro = YES;
    _ownsMedia = pmunlock::playChapterStoryMedia(path,nil,_program.chapterName,^(BOOL played){
        PMNativeOSActions *owner = weak;
        if (![owner isCurrent]) return;
        owner->_ownsMedia = NO;
        if (!played) { owner->_intro=NO; completion(NO); return; }
        [owner->_program markEntryMovieSeen:^(BOOL saved){
            PMNativeOSActions *active=weak;
            if (![active isCurrent]) return;
            active->_intro=NO;
            if (!saved) PMDiagnosticsWrite("Chapter OS: could not persist entry movie completion");
            completion(saved);
        }];
    },true);
    if (!_ownsMedia) _intro=NO;
    return _ownsMedia;
}

- (BOOL)playIntro:(NSDictionary *)row completion:(void (^)(BOOL))completion {
    if (![self ready] || !gameWindow()) return NO;
    NSString *key = row[@"challengeID"];
    if (!key) return NO;
    // Only trust media paired with the challenge in this loaded program. Card overrides
    // may customize presentation, never the media paths or the VM's challenge state.
    NSUInteger i = [_program.challengeRows indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        return [key isEqual:entry[@"challengeID"]];
    }];
    if (i == NSNotFound || i >= (NSUInteger)_program.page->challengeCount) return NO;
    NSDictionary *canonical = _program.challengeRows[i];
    const PMOSChallenge &challenge = _program.page->challenges[i];
    if (challenge.state == PMOSChallengeLocked || [canonical[@"replaySongs"] count]) return NO;
    _intro = YES;
    [self playClip:0 challenge:i title:row[@"title"] ?: canonical[@"title"] completion:completion];
    return YES;
}
- (void)playClip:(NSUInteger)index challenge:(NSUInteger)i title:(NSString *)title completion:(void (^)(BOOL))completion {
    PMNativeOSProgram *program = _program;
    NSDictionary *canonical = program.challengeRows[i];
    NSArray *paths = canonical[@"intro"];
    __weak PMNativeOSActions *weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{@autoreleasepool {
        const auto &challenge = program.page->challenges[i];
        BOOL end = index == paths.count && paths.count == (NSUInteger)challenge.introCount;
        NSString *path = nil;
        if (paths.count == (NSUInteger)challenge.introCount && index < paths.count) {
            NSString *name = @(challenge.intro[index]);
            NSString *verified = [name hasPrefix:@"@stock/"] ? PMResolveStockIntro(name) : PMOSArtPath([PMContentStore.shared asset:program.chapter], name);
            NSString *ext = verified.pathExtension.lowercaseString;
            if ([verified isEqual:paths[index]] && ( [ext isEqual:@"gif"] || [ext isEqual:@"mp4"]) &&
                [[NSFileManager.defaultManager attributesOfItemAtPath:verified error:nil][NSFileType] isEqual:NSFileTypeRegular]) path = verified;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            PMNativeOSActions *owner = weak;
            if (![owner isCurrent] || !owner->_intro) return;
            if (end) { owner->_intro = NO; completion(YES); return; }
            if (path && gameWindow()) {
                owner->_ownsMedia = pmunlock::playChapterStoryMedia(path, canonical[@"art"], title, ^(BOOL ok) {
                    PMNativeOSActions *visit = weak;
                    if (!visit) return;
                    visit->_ownsMedia = NO;
                    if (![visit isCurrent] || !visit->_intro) return;
                    if (ok) [visit playClip:index+1 challenge:i title:title completion:completion];
                    else { visit->_intro = NO; completion(NO); }
                });
                if (owner->_ownsMedia) return;
            }
            owner->_intro = NO;
            completion(NO);
        });
    }});
}

- (BOOL)reveal:(const PMOSAction *)action fromNode:(NSInteger)index completion:(void (^)(PMNativeRevealChoice))completion {
    if (![self ready] || self.cardOnly || !action || !action->revealTitle[0]) return NO;
    const PMOSPage &page = *_program.page;
    NSInteger target = action->element;
    if (index < 0 || index >= page.nodes || target < 0 || target >= page.nodes ||
        page.elements[index].screen != page.elements[target].screen || action->song < 0 ||
        (NSUInteger)action->song > _program.order.count || page.elements[index].songSuppressed ||
        page.elements[target].songSuppressed || (action->song && !_program.visibleBySong[_program.order[action->song - 1]])) return NO;
    UIWindow *host = gameWindow();
    CGRect start = normalizedRect(page, index), end = normalizedRect(page, target);
    NSString *title = [NSString stringWithUTF8String:action->revealTitle];
    NSString *body = [NSString stringWithUTF8String:action->revealText];
    if (!host || !title || !body || CGRectIsEmpty(start) || CGRectIsEmpty(end)) return NO;
    PMNativeFocusPanel *panel = [[PMNativeFocusPanel alloc] initWithFrame:host.bounds];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.aspect = page.aspect;
    panel.sourceRect = start; panel.targetRect = end;
    panel.source = [UIView new]; panel.target = [UIView new];
    [panel addSubview:panel.source]; [panel addSubview:panel.target];
    _reveal = [[PMOSRevealView alloc] initWithTitle:title text:body hasSong:action->song > 0];
    _reveal.frame = panel.bounds;
    [panel addSubview:_reveal];
    _panel = panel;
    [host addSubview:panel]; [panel layoutIfNeeded];
    __weak PMNativeOSActions *weak = self;
    _resignObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            PMNativeOSActions *owner = weak;
            if (!owner || !owner->_reveal) return;
            [owner dismissPanel];
            if ([owner isCurrent]) completion(PMNativeRevealContinue);
        }];
    [_reveal focusFrom:panel.source to:panel.target completion:^(PMOSRevealChoice choice) {
        PMNativeOSActions *owner = weak;
        if (!owner) return;
        [owner dismissPanel];
        if ([owner isCurrent]) completion(choice == PMOSRevealStart ? PMNativeRevealStart :
                                          choice == PMOSRevealDetail ? PMNativeRevealDetail : PMNativeRevealContinue);
    }];
    return YES;
}

- (BOOL)checkpoint:(const PMOSAction *)action resume:(void (^)(NSDictionary *))resume leave:(void (^)(void))leave {
    if (![self ready] || !action || (action->checkpoint != 1 && action->checkpoint != 2)) return NO;
    UIWindow *host = gameWindow();
    if (!host) return NO;
    NSMutableDictionary *fields = [@{@"chapter":_program.chapter, @"scriptHash":_program.scriptHash,
                                     @"token":NSUUID.UUID.UUIDString} mutableCopy];
    if (action->song > 0 && (NSUInteger)action->song <= _program.order.count && action->dest == -1) {
        NSString *sid = _program.order[action->song - 1];
        if (!_program.visibleBySong[sid]) return NO;
        fields[@"songID"] = sid;
        if (action->difficulty[0]) {
            NSString *difficulty = [NSString stringWithUTF8String:action->difficulty];
            if (!difficulty) return NO;
            fields[@"difficulty"] = difficulty;
        }
    } else if (action->song == 0 && action->dest >= 0 && (NSUInteger)action->dest < _program.screens.count) {
        fields[@"page"] = _program.screens[action->dest];
    } else return NO;

    NSDictionary *record = [fields copy];
    BOOL relaunch = action->checkpoint == 2;
    if (relaunch && !PMOSSaveCheckpoint(record, nullptr)) return NO;
    UIView *panel = [[UIView alloc] initWithFrame:host.bounds];
    panel.backgroundColor = UIColor.blackColor;
    panel.accessibilityViewIsModal = YES;
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UILabel *message = [UILabel new];
    message.numberOfLines = 0; message.textAlignment = NSTextAlignmentCenter; message.textColor = UIColor.whiteColor;
    message.text = relaunch ? @"章节连接已中断。重新打开游戏可继续。" : @"章节连接已中断。";
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:relaunch ? @"返回" : @"重新连接" forState:UIControlStateNormal];
    __weak PMNativeOSActions *weak = self;
    __weak UIView *weakPanel = panel;
    [button addAction:[UIAction actionWithHandler:^(UIAction *sender) {
        PMNativeOSActions *owner = weak;
        if (![owner isCurrent] || !weakPanel || owner->_panel != weakPanel) return;
        [owner dismissPanel];
        if (relaunch) leave(); else resume(record);
    }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[message,button]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
                                             [stack.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor],
                                             [stack.widthAnchor constraintLessThanOrEqualToAnchor:panel.widthAnchor multiplier:.9]]];
    _panel = panel; [host addSubview:panel];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, message);
    return YES;
}
- (void)dismissPanel {
    if (_resignObserver) { [NSNotificationCenter.defaultCenter removeObserver:_resignObserver]; _resignObserver = nil; }
    [_reveal cancel]; _reveal = nil;
    [_panel removeFromSuperview]; _panel = nil;
}
- (void)invalidate {
    _current = nil;
    _intro = NO;
    [self dismissPanel];
    if (_ownsMedia) { _ownsMedia = NO; PMCancelUnlockMedia(); }
}
@end
