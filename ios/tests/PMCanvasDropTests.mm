// Hosted iOS XCTest. Link the chapter OS presentation unit into the test host.
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

@interface PMChapterCanvas : UIView
@property(nonatomic,copy) NSArray *nodes;
@property(nonatomic,copy) void (^runHandler)(NSInteger);
@property(nonatomic,readonly) NSArray<UIControl *> *items;
@property(nonatomic,readonly) NSUInteger visit;
- (void)displayPage:(NSInteger)index;
- (void)setElement:(NSInteger)index visible:(BOOL)visible;
- (void)dragPiece:(UIPanGestureRecognizer *)pan;
@end
@interface PMTestDropPan : UIPanGestureRecognizer
@property(nonatomic,weak) UIView *piece;
@property(nonatomic) UIGestureRecognizerState phase;
@property(nonatomic) CGPoint delta;
@end
@implementation PMTestDropPan
- (UIView *)view { return self.piece; }
- (UIGestureRecognizerState)state { return self.phase; }
- (CGPoint)translationInView:(UIView *)view { return self.delta; }
@end

@interface PMCanvasDropTests : XCTestCase
@end
@implementation PMCanvasDropTests
- (void)testRectangleDropCrossesFrameAndOldPanCannotDispatch {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0,0,400,200)];
    window.rootViewController = [UIViewController new];
    PMChapterCanvas *canvas = [[PMChapterCanvas alloc] initWithFrame:window.bounds];
    [window.rootViewController.view addSubview:canvas];
    window.hidden = NO;
    NSDictionary *(^node)(NSInteger,CGRect) = ^NSDictionary *(NSInteger parent, CGRect rect) {
        return @{@"screen":@0,@"parent":@(parent),@"dest":@(-1),@"rect":[NSValue valueWithCGRect:rect]};
    };
    NSMutableDictionary *pieceNode = [node(0,CGRectMake(.25,.4,.5,.2)) mutableCopy];
    pieceNode[@"dropIndex"]=@2; pieceNode[@"handler"]=@YES;
    canvas.nodes = @[node(-1,CGRectMake(0,0,.25,1)),pieceNode,node(-1,CGRectMake(.7,.4,.2,.2))];
    __block NSInteger calls = 0;
    canvas.runHandler = ^(NSInteger index){ XCTAssertEqual(index,1); ++calls; };
    [canvas displayPage:0]; [canvas layoutIfNeeded];
    PMTestDropPan *pan = [PMTestDropPan new];
    UIControl *piece = canvas.items[1]; pan.piece = piece;
    [piece setValue:@(canvas.visit) forKey:@"dragVisit"];
    CGPoint home = piece.center;
    void (^gesture)(CGPoint) = ^(CGPoint movement){
        pan.delta=CGPointZero; pan.phase=UIGestureRecognizerStateBegan; [canvas dragPiece:pan];
        pan.delta=movement; pan.phase=UIGestureRecognizerStateEnded; [canvas dragPiece:pan];
    };
    [piece sendActionsForControlEvents:UIControlEventTouchUpInside];
    gesture(CGPointMake(90,0)); XCTAssertTrue(CGPointEqualToPoint(home,piece.center));
    [canvas setElement:2 visible:NO]; gesture(CGPointMake(270,0)); XCTAssertEqual(calls,0);
    [canvas setElement:2 visible:YES]; gesture(CGPointMake(270,0)); XCTAssertEqual(calls,1);
    XCTAssertEqual(piece.superview,canvas); XCTAssertTrue(CGPointEqualToPoint(piece.center,canvas.items[2].center));
    [canvas displayPage:0]; [canvas layoutIfNeeded];
    XCTAssertTrue(CGPointEqualToPoint(canvas.items[1].center,canvas.items[2].center));
    gesture(CGPointMake(270,0)); XCTAssertEqual(calls,1);
    window.hidden = YES;
}
@end
