// Shared by the existing score callbacks. UIKit fades use wall time at any playback rate.
namespace timingHints {
static UILabel *labels[24];
static unsigned cursor = 0;
static std::set<float> shown;
static bool enabled = false;
static bool showBad = false;

void clear() {
    enabled = false;
    showBad = false;
    shown.clear();
    cursor = 0;
    for (auto &label : labels) {
        [label.layer removeAllAnimations];
        [label removeFromSuperview];
        label = nil;
    }
}

UIView *gameView() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController.viewIfLoaded.window == window)
                return window.rootViewController.viewIfLoaded;
        }
    }
    return nil;
}

void show(float code, float offset, const V3 *hit) {
    if (!enabled || !std::isfinite(code) || !std::isfinite(offset) || offset == 0 || pmpractice::paused() || inResult) return;
    if (!shown.insert(code).second) return;
    UIView *view = gameView();
    if (!view) return;
    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    if (width < 100 || height < 60) return;
    CGFloat x = CGRectGetMidX(bounds), y = CGRectGetMinY(bounds) + height * .20;
    CGFloat font = std::clamp(height * .042, (CGFloat)14, (CGFloat)32);
    if (hit) {
        try {
            auto &r = R();
            P camera = r.stat(r.type("UnityEngine","Camera"),"get_main");
            if (camera) {
                V3 point = *hit;
                auto viewport = r.unbox<V3>(r.call(camera,"WorldToViewportPoint",{"UnityEngine.Vector3"},{&point}));
                if (!std::isfinite(viewport.x) || !std::isfinite(viewport.y) || viewport.z <= 0) return;
                x = CGRectGetMinX(bounds) + viewport.x * width;
                y = CGRectGetMinY(bounds) + (1 - viewport.y) * height - font * 1.6;
            }
        } catch (const std::exception &) { /* Use HUD position if the camera is unavailable. */ }
    }
    // Bad has no hit position. Reuse one HUD label so consecutive Bads stay legible.
    const unsigned slot = hit ? 1 + cursor++ % 23 : 0;
    UILabel *label = labels[slot];
    if (!label) {
        label = [[UILabel alloc] init];
        label.userInteractionEnabled = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.shadowColor = [UIColor colorWithWhite:0 alpha:.7];
        label.shadowOffset = CGSizeMake(0,1);
        labels[slot] = label;
    }
    [label.layer removeAllAnimations];
    label.font = [UIFont boldSystemFontOfSize:font];
    label.text = offset > 0 ? @"Late" : @"Early";
    label.textColor = offset > 0 ? [UIColor colorWithRed:1 green:.62 blue:.56 alpha:1] : [UIColor colorWithRed:.58 green:.85 blue:1 alpha:1];
    [label sizeToFit];
    CGFloat halfWidth = CGRectGetWidth(label.bounds)/2, halfHeight = CGRectGetHeight(label.bounds)/2;
    label.center = CGPointMake(std::clamp(x,CGRectGetMinX(bounds)+halfWidth,CGRectGetMaxX(bounds)-halfWidth),
                               std::clamp(y,CGRectGetMinY(bounds)+halfHeight,CGRectGetMaxY(bounds)-halfHeight));
    [view addSubview:label];
    label.alpha = 1;
    [UIView animateWithDuration:.20 delay:.45 options:UIViewAnimationOptionCurveLinear animations:^{ label.alpha = 0; } completion:nil];
}
}
