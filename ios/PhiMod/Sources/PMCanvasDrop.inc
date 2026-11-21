// Each recognizer belongs to one piece. A page visit is captured at touch-down,
// before UIKit's pan threshold. Settling animations never dispatch actions.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)pan shouldReceiveTouch:(UITouch *)touch {
    PMCanvasItem *piece = (PMCanvasItem *)pan.view;
    if (touch.view != piece || self.pending || self.dragging || !self.clockRunning ||
        [piece.layer animationForKey:@"dropSettle"]) return NO;
    piece.dragVisit = self.visit;
    return YES;
}

- (void)discardDrag {
    self.dragging.layer.mask = nil;
    [self.dragPreview removeFromSuperview];
    self.dragPreview = nil;
    self.dragging = nil;
}

- (BOOL)visibleForDrop:(UIView *)node {
    for (UIView *v = node; v; v = v.superview) {
        CALayer *layer = v.layer.presentationLayer ?: v.layer;
        if (v.hidden || layer.opacity <= .01) return NO;
        if (v == self) return self.window != nil;
    }
    return NO;
}

- (BOOL)target:(PMCanvasItem *)target containsCanvasPoint:(CGPoint)point {
    if (![self visibleForDrop:target]) return NO;
    for (UIView *v = target; v; v = v.superview) {
        if ((v == target || v.clipsToBounds || v == self) &&
            !CGRectContainsPoint(v.bounds, [v convertPoint:point fromView:self])) return NO;
        if (v == self) break;
    }
    return YES;
}

- (void)layoutPieces {
    // Size in the declared parent, even after placing in a different frame.
    for (PMCanvasItem *item in self.items) {
        CGRect r = item.relative;
        CGSize p = item.layoutParent.bounds.size;
        CGRect rect = CGRectMake(r.origin.x*p.width, r.origin.y*p.height, r.size.width*p.width, r.size.height*p.height);
        if (item.placed) item.bounds = (CGRect){CGPointZero, rect.size};
        else item.frame = rect;
    }
    // Forward target references are legal. All target frames are now laid out.
    for (PMCanvasItem *item in self.items) {
        if (item.placed) item.center = item.dropTarget.center;
    }
}

- (void)dragPiece:(UIPanGestureRecognizer *)pan {
    PMCanvasItem *piece = (PMCanvasItem *)pan.view;
    BOOL current = self.clockRunning && !self.pending && piece.dragVisit == self.visit &&
        [self visibleForDrop:piece] && [self.items containsObject:piece];
    if (pan.state == UIGestureRecognizerStateBegan && current && !self.dragging) {
        // A canvas-level preview can leave a clipped source frame. Keep the live
        // touch receiver in place until UIKit has delivered the final position.
        UIView *preview = [piece snapshotViewAfterScreenUpdates:NO];
        if (!preview) return;
        preview.userInteractionEnabled = NO;
        preview.frame = [piece convertRect:piece.bounds toView:self];
        self.dragCanvasSize = self.bounds.size;
        self.dragOrigin = preview.center;
        self.dragging = piece;
        self.dragPreview = preview;
        [self addSubview:preview];
        piece.layer.mask = [CALayer layer];
    }
    if (self.dragging != piece) return;
    if (!current || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [self discardDrag];
        return;
    }
    CGPoint delta = [pan translationInView:self];
    CGPoint release = CGPointMake(self.dragOrigin.x + delta.x, self.dragOrigin.y + delta.y);
    self.dragPreview.center = release;
    if (pan.state != UIGestureRecognizerStateEnded) return;

    PMCanvasItem *target = piece.dropTarget;
    BOOL accept = [self target:target containsCanvasPoint:release];
    [self discardDrag];
    if (accept) {
        piece.placed = YES;
        [self.placements addIndex:piece.tag];
        if (piece.superview != target.superview) [target.superview addSubview:piece];
        [piece.superview bringSubviewToFront:piece];
        piece.center = target.center;
    }
    // Animate the visual position only. Failure keeps the prior layout anchor.
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *settle = [CABasicAnimation animationWithKeyPath:@"position"];
        settle.fromValue = [NSValue valueWithCGPoint:[piece.superview convertPoint:release fromView:self]];
        settle.toValue = [NSValue valueWithCGPoint:piece.center];
        settle.duration = .16;
        settle.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [piece.layer addAnimation:settle forKey:@"dropSettle"];
    }
    if (accept && self.runHandler) self.runHandler(piece.tag);
}
