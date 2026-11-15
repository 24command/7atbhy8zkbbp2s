#import "PMChapterManageUI.h"
#import "PMContentStore.h"
#import "PMChapterEditing.h"
#import "PMImageCropController.h"
#include "PMContentRuntime.hpp"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
@interface PMChapterSongList:UITableViewController<UISearchResultsUpdating,UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString*chapter;
@property(nonatomic,strong) NSArray*all;
@property(nonatomic,strong) NSArray*filtered;
@property(nonatomic,strong) NSSet*members;
@property(nonatomic,strong) NSMutableSet*selected;
@property(nonatomic,strong) UISearchController*search;
@property(nonatomic,strong) UISegmentedControl*scope;
@property(nonatomic,copy) NSString*coverID;
@end
// One request per presentation container, including the action-sheet handoff.
// Do not borrow PMContentUI's busy flag: cancelling must not strand its toolbar.
static char PMChapterPickerRequestKey;

static NSDictionary *PMChapterPickerDictionary(id value) {
  return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static NSArray *PMChapterPickerArray(id value) {
  return [value isKindOfClass:NSArray.class] ? value : @[];
}
static NSString *PMChapterPickerString(id value) {
  if (![value isKindOfClass:NSString.class]) return nil;
  NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return text.length ? text : nil;
}
static NSString *PMChapterPickerReadableTitle(id value) {
  NSString *text = PMChapterPickerString(value);
  if (!text) return nil;
  // Cached native metadata may contain localization keys, not display strings.
  // Never guess a translation or invoke the game runtime from this UIKit page.
  if ([text hasPrefix:@"\\"] || [text hasPrefix:@"#"] || [text hasPrefix:@"$"] || [text hasPrefix:@"@"] ||
      [text hasPrefix:@"{"] || [text hasPrefix:@"<"]) return nil;
  NSString *pattern = @"(?i)^(?:(?:chapter(?:name|title|s)?|mainstory|sidestory|collection|localization|localisation|i18n)(?:[0-9][a-z0-9_./:-]*|[_.:/-][a-z0-9_./:-]+)|chapter(?:name|title)|[a-z0-9]+(?:_[a-z0-9]+)+|(?:in|loc|locale|lang|text|ui)[./:][a-z0-9_./:-]+)$";
  if ([text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound) return nil;
  return text;
}
static NSArray<NSDictionary *> *PMChapterPickerRows(void) {
  NSDictionary *db = PMChapterPickerDictionary([PMContentStore.shared snapshot]);
  NSDictionary *official = PMChapterPickerDictionary(pmcontent::cachedOfficialSnapshot());
  NSMutableArray *chapters = [PMChapterPickerArray(db[@"chapters"]) mutableCopy];
  [chapters addObjectsFromArray:PMChapterPickerArray(official[@"chapters"])];
  NSDictionary *overrides = PMChapterPickerDictionary(db[@"chapterOverrides"]);
  NSMutableArray *rows = [NSMutableArray new];
  NSMutableSet *seen = [NSMutableSet new];
  for (id value in chapters) {
    NSDictionary *chapter = PMChapterPickerDictionary(value);
    NSString *identifier = PMChapterPickerString(chapter[@"id"]) ?: PMChapterPickerString(chapter[@"chapterCode"]);
    if (!identifier || [seen containsObject:identifier]) continue;
    NSDictionary *info = PMChapterPickerDictionary(chapter[@"songInfo"]);
    NSDictionary *patch = PMChapterPickerDictionary(overrides[identifier]);
    NSString *title = PMChapterPickerReadableTitle(patch[@"title"]) ?:
        PMChapterPickerReadableTitle(chapter[@"name"]) ?:
        PMChapterPickerReadableTitle(chapter[@"title"]) ?:
        PMChapterPickerReadableTitle(info[@"title"]) ?: identifier;
    [rows addObject:@{@"id":identifier, @"title":title}];
    [seen addObject:identifier];
  }
  return rows;
}

@interface PMChapterPickerPage : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,copy) NSArray<NSDictionary *> *chapters;
@property(nonatomic,copy) void (^chosen)(NSString *);
@property(nonatomic,weak) UIViewController *source;
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) BOOL waiting;
@property(nonatomic) BOOL presentationStarted;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL finishing;
- (void)presentWhenReady;
- (void)releaseRequest;
@end

@implementation PMChapterPickerPage
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"\u9009\u62e9\u76ee\u6807\u7ae0\u8282";
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
  self.navigationItem.leftBarButtonItem.enabled = NO;
  self.tableView.userInteractionEnabled = NO;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 64;
  self.tableView.alwaysBounceVertical = YES;
  if (!self.chapters.count) {
    UILabel *empty = [UILabel new];
    empty.text = @"\u6682\u65e0\u53ef\u9009\u7ae0\u8282";
    empty.textAlignment = NSTextAlignmentCenter;
    empty.numberOfLines = 0;
    empty.textColor = UIColor.secondaryLabelColor;
    self.tableView.backgroundView = empty;
  }
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
  return self.chapters.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
  UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"ChapterChoice"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChapterChoice"];
  NSDictionary *chapter = self.chapters[index.row];
  cell.textLabel.text = chapter[@"title"];
  cell.textLabel.numberOfLines = 0;
  cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  cell.textLabel.adjustsFontForContentSizeCategory = YES;
  cell.detailTextLabel.text = [chapter[@"title"] isEqualToString:chapter[@"id"]] ? nil : chapter[@"id"];
  cell.detailTextLabel.numberOfLines = 0;
  cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
  cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
  return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
  [table deselectRowAtIndexPath:index animated:YES];
  if (index.row < 0 || (NSUInteger)index.row >= self.chapters.count) return;
  [self finishWithIdentifier:self.chapters[index.row][@"id"]];
}
- (void)cancel { [self finishWithIdentifier:nil]; }
- (void)finishWithIdentifier:(NSString *)identifier {
  UINavigationController *navigation = self.navigationController;
  if (!self.ready || self.finishing || !navigation.presentingViewController ||
      navigation.isBeingPresented || navigation.isBeingDismissed || navigation.transitionCoordinator) return;
  self.finishing = YES;
  self.ready = NO;
  self.tableView.userInteractionEnabled = NO;
  self.navigationItem.leftBarButtonItem.enabled = NO;
  [navigation dismissViewControllerAnimated:YES completion:^{
    void (^callback)(NSString *) = self.chosen;
    UIViewController *source = self.source, *owner = self.owner;
    BOOL visible = source.isViewLoaded && source.view.window && owner &&
        !source.isBeingDismissed && !owner.isBeingDismissed;
    [self releaseRequest]; // Clear the gate BEFORE callback: it may immediately reopen.
    if (visible && identifier.length && callback) callback(identifier);
  }];
}
- (void)releaseRequest {
  self.ready = NO;
  self.waiting = NO;
  self.chosen = nil;
  UIViewController *owner = self.owner;
  if (owner && objc_getAssociatedObject(owner, &PMChapterPickerRequestKey) == self)
    objc_setAssociatedObject(owner, &PMChapterPickerRequestKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
  if (!self.finishing) [self releaseRequest]; // Interactive dismissal is cancellation, never a choice.
}
- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  // Also release on an external/programmatic dismissal of the containing UI.
  if (self.presentationStarted && !self.finishing &&
      (self.navigationController.isBeingDismissed || !self.navigationController.presentingViewController))
    [self releaseRequest];
}
- (void)retryAfterTransitionOf:(UIViewController *)controller {
  if (self.waiting) return;
  self.waiting = YES;
  __weak PMChapterPickerPage *weakSelf = self;
  dispatch_block_t retry = ^{
    PMChapterPickerPage *page = weakSelf;
    if (!page.waiting) return;
    page.waiting = NO;
    [page presentWhenReady];
  };
  id<UIViewControllerTransitionCoordinator> transition = controller.transitionCoordinator;
  if (transition && [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    dispatch_async(dispatch_get_main_queue(), retry);
  }]) return;
  // UIKit may expose a transitioning flag before/after it exposes a coordinator.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), retry);
}
- (void)presentWhenReady {
  UIViewController *owner = self.owner, *source = self.source;
  if (!owner || objc_getAssociatedObject(owner, &PMChapterPickerRequestKey) != self || self.presentationStarted) return;
  if (!source || NSProcessInfo.processInfo.systemUptime >= self.deadline) { [self releaseRequest]; return; }
  if (owner.isBeingPresented || owner.isBeingDismissed || owner.transitionCoordinator) {
    [self retryAfterTransitionOf:owner]; return;
  }
  if (source.isBeingPresented || source.isBeingDismissed || source.transitionCoordinator) {
    [self retryAfterTransitionOf:source]; return;
  }
  UIViewController *modal = source.presentedViewController ?: owner.presentedViewController;
  if (modal) {
    if (modal.isBeingPresented || modal.isBeingDismissed || modal.transitionCoordinator) {
      [self retryAfterTransitionOf:modal]; return;
    }
    // Only consume the operation actionSheet, never dismiss an unrelated editor/alert.
    if (![modal isKindOfClass:UIAlertController.class] ||
        ((UIAlertController *)modal).preferredStyle != UIAlertControllerStyleActionSheet) {
      [self releaseRequest]; return;
    }
    self.waiting = YES;
    [modal dismissViewControllerAnimated:YES completion:^{
      self.waiting = NO;
      [self presentWhenReady];
    }];
    return;
  }
  if (!source.isViewLoaded || !source.view.window || !owner.isViewLoaded || !owner.view.window) {
    [self releaseRequest]; return;
  }
  self.chapters = PMChapterPickerRows();
  UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:self];
  navigation.modalPresentationStyle = owner.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad
      ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
  navigation.preferredContentSize = CGSizeMake(540, 620);
  [navigation setNavigationBarHidden:NO animated:NO];
  navigation.presentationController.delegate = self;
  self.presentationStarted = YES;
  [owner presentViewController:navigation animated:YES completion:^{
    if (objc_getAssociatedObject(owner, &PMChapterPickerRequestKey) == self &&
        navigation.presentingViewController && !navigation.isBeingDismissed && !owner.isBeingDismissed) {
      self.ready = YES;
      self.tableView.userInteractionEnabled = YES;
      self.navigationItem.leftBarButtonItem.enabled = YES;
    } else [self releaseRequest];
  }];
}
@end

void PMChooseChapter(UIViewController *presenter, void (^chosen)(NSString *)) {
  // Leave the UIAlertAction handler first, so UIKit can start its automatic dismissal.
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *source = presenter;
    if ([source isKindOfClass:UIAlertController.class]) source = source.presentingViewController;
    if (!source || !chosen) return;
    UIViewController *owner = source;
    while (owner.parentViewController) owner = owner.parentViewController;
    if (objc_getAssociatedObject(owner, &PMChapterPickerRequestKey)) return;
    PMChapterPickerPage *page = [[PMChapterPickerPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
    page.source = source;
    page.owner = owner;
    page.chosen = chosen;
    page.deadline = NSProcessInfo.processInfo.systemUptime + 5.0;
    objc_setAssociatedObject(owner, &PMChapterPickerRequestKey, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Bound an abandoned UIKit handoff even if its completion never arrives.
    __weak PMChapterPickerPage *weakPage = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PMChapterPickerPage *pending = weakPage;
      if (!pending.presentationStarted || !pending.navigationController.presentingViewController)
        [pending releaseRequest];
    });
    [page presentWhenReady];
  });
}
@implementation PMChapterSongList
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"\u7ae0\u8282\u66f2\u76ee";self.selected=[NSMutableSet new];self.scope=[[UISegmentedControl alloc]initWithItems:@[@"\u672c\u7ae0\u8282\u66f2\u76ee",@"\u5168\u90e8\u5b98\u8c31"]];self.scope.selectedSegmentIndex=0;[self.scope addTarget:self action:@selector(filter) forControlEvents:UIControlEventValueChanged];self.navigationItem.titleView=self.scope;
 self.search=[UISearchController new];self.search.searchResultsUpdater=self;self.search.obscuresBackgroundDuringPresentation=NO;self.navigationItem.searchController=self.search;self.definesPresentationContext=YES;
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];self.navigationController.toolbarHidden=NO;[self reload];
}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)message:(NSString*)text{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"PhiMod" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)reload{
 NSDictionary*db=[PMContentStore.shared snapshot],*official=pmcontent::cachedOfficialSnapshot();self.members=[NSSet setWithArray:PMChapterSongIDs(db,official,self.chapter)];NSMutableArray*list=[NSMutableArray new];NSDictionary*map=PMOfficialSongMap(official);
 for(NSString*id in [[map allKeys]sortedArrayUsingSelector:@selector(compare:)]){NSDictionary*s=map[id],*patch=db[@"overrides"][id];[list addObject:@{@"id":id,@"title":patch[@"songsName"]?:s[@"songsName"]?:id,@"composer":patch[@"composer"]?:s[@"composer"]?:@"",@"official":@YES}];}
 for(NSDictionary*s in db[@"songs"])if([self.members containsObject:s[@"id"]]){NSMutableDictionary*v=[s mutableCopy];v[@"official"]=@NO;[list addObject:v];}self.all=list;[self filter];
}
- (void)filter{NSString*q=self.search.searchBar.text?:@"";BOOL official=self.scope.selectedSegmentIndex==1;NSMutableArray*a=[NSMutableArray new];for(NSDictionary*s in self.all){if(official?![s[@"official"]boolValue]:![self.members containsObject:s[@"id"]])continue;NSString*t=[NSString stringWithFormat:@"%@ %@ %@",s[@"title"],s[@"composer"],s[@"id"]];if(!q.length||[t rangeOfString:q options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound)[a addObject:s];}self.filtered=a;[self toolbar];[self.tableView reloadData];}
- (void)updateSearchResultsForSearchController:(UISearchController*)search{[self filter];}
- (void)toolbar{UIBarButtonItem*add=[[UIBarButtonItem alloc]initWithTitle:@"\u6dfb\u52a0\u5230\u672c\u7ae0\u8282" style:UIBarButtonItemStylePlain target:self action:@selector(addHere)];UIBarButtonItem*move=[[UIBarButtonItem alloc]initWithTitle:@"\u79fb\u52a8\u5230\u672c\u7ae0\u8282" style:UIBarButtonItemStylePlain target:self action:@selector(moveHere)];add.enabled=move.enabled=self.selected.count>0;self.toolbarItems=@[add,[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],move];self.navigationItem.prompt=[NSString stringWithFormat:@"\u5df2\u9009 %lu \u9996\uff1b\u70b9\u51fb\u53f3\u4fa7\u4fe1\u606f\u6309\u94ae\u7f16\u8f91\u66f2\u7ed8\u548c\u4fe1\u606f",(unsigned long)self.selected.count];}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section{return self.filtered.count;}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)index{UITableViewCell*c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDictionary*s=self.filtered[index.row];c.textLabel.text=[NSString stringWithFormat:@"%@%@",[self.selected containsObject:s[@"id"]]?@"[x] ":@"",s[@"title"]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@  %@",s[@"composer"],[self.members containsObject:s[@"id"]]?@"\u5df2\u5728\u672c\u7ae0\u8282":s[@"id"]];c.accessoryType=UITableViewCellAccessoryDetailButton;return c;}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)index{[table deselectRowAtIndexPath:index animated:YES];NSString*id=self.filtered[index.row][@"id"];if([self.selected containsObject:id])[self.selected removeObject:id];else[self.selected addObject:id];[self toolbar];[table reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];}
- (void)assign:(BOOL)move{NSError*e=nil;if(![PMContentStore.shared assignSongs:self.selected.allObjects toChapter:self.chapter move:move error:&e]){[self message:e.localizedDescription];return;}[self.selected removeAllObjects];[self reload];[self message:@"\u5df2\u4fdd\u5b58\uff0c\u8bf7\u8fd4\u56de\u8c31\u5e93\u5e94\u7528\u5230\u6e38\u620f\u3002"];}
- (void)addHere{[self assign:NO];}
- (void)moveHere{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u79fb\u52a8\u9009\u4e2d\u66f2\u76ee\uff1f" message:@"\u4ece\u539f\u7ae0\u8282\u79fb\u51fa\u9009\u4e2d\u66f2\u76ee\uff0c\u4fdd\u7559\u539f\u7248\u97f3\u9891\u3001\u8c31\u9762\u548c\u6210\u7ee9\u3002" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"\u79fb\u52a8" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self assign:YES];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView*)table accessoryButtonTappedForRowWithIndexPath:(NSIndexPath*)index{
 NSDictionary*s=self.filtered[index.row];UIAlertController*a=[UIAlertController alertControllerWithTitle:s[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"\u66f4\u6362\u66f2\u76ee\u5c01\u9762" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){self.coverID=s[@"id"];UIDocumentPickerViewController*p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u7f16\u8f91\u66f2\u540d / \u66f2\u5e08" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self edit:s];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=[table cellForRowAtIndexPath:index];a.popoverPresentationController.sourceRect=CGRectMake(10,10,1,1);[self presentViewController:a animated:YES completion:nil];
}
- (void)edit:(NSDictionary*)song{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u66f2\u76ee\u4fe1\u606f" message:@"\u4ec5\u4fee\u6539\u672c\u5730\u663e\u793a\u4fe1\u606f\uff0c\u4e0d\u6539\u53d8\u8c31\u9762\u548c\u6210\u7ee9\u3002" preferredStyle:UIAlertControllerStyleAlert];for(NSString*k in @[@"title",@"composer"])[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.text=song[k];f.placeholder=k;}];[a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"\u4fdd\u5b58" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSMutableDictionary*db=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:[PMContentStore.shared snapshot] options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];NSString*id=song[@"id"],*title=a.textFields[0].text?:@"",*composer=a.textFields[1].text?:@"";if([song[@"official"]boolValue]){NSMutableDictionary*all=[db[@"overrides"]mutableCopy]?:[NSMutableDictionary new],*patch=[all[id]mutableCopy]?:[NSMutableDictionary new];patch[@"songsName"]=title;patch[@"songsTitle"]=title;patch[@"composer"]=composer;all[id]=patch;db[@"overrides"]=all;}else for(NSMutableDictionary*s in db[@"songs"])if([s[@"id"]isEqual:id]){s[@"title"]=title;s[@"composer"]=composer;}NSError*e=nil;if(![PMContentStore.shared commit:db error:&e])[self message:e.localizedDescription];[self reload];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)documentPicker:(UIDocumentPickerViewController*)picker didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls{NSURL*url=urls.firstObject;BOOL scope=[url startAccessingSecurityScopedResource];UIImage*image=[UIImage imageWithContentsOfFile:url.path];if(scope)[url stopAccessingSecurityScopedResource];NSString*id=self.coverID;self.coverID=nil;[picker dismissViewControllerAnimated:YES completion:^{if(!image){[self message:@"\u65e0\u6cd5\u8bfb\u53d6\u56fe\u7247"];return;}PMImageCropController*crop=[[PMImageCropController alloc]initWithImage:image aspect:16.0/9.0 completion:^(UIImage*result){if(result){NSError*error=nil;if(![PMContentStore.shared replaceImageData:UIImagePNGRepresentation(result) identifier:id error:&error])[self message:error.localizedDescription];else[self message:@"\u5c01\u9762\u5df2\u4fdd\u5b58\uff0c\u8bf7\u5e94\u7528\u5230\u6e38\u620f\u3002"];}}];crop.allowsCompleteCover=YES;UINavigationController*nav=[[UINavigationController alloc]initWithRootViewController:crop];nav.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:nav animated:YES completion:nil];}];}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)picker{self.coverID=nil;[picker dismissViewControllerAnimated:YES completion:nil];}
@end
void PMShowChapterSongs(UIViewController*presenter,NSString*chapter){PMChapterSongList*c=[[PMChapterSongList alloc]initWithStyle:UITableViewStyleInsetGrouped];c.chapter=chapter;UINavigationController*nav=[[UINavigationController alloc]initWithRootViewController:c];nav.modalPresentationStyle=UIModalPresentationFullScreen;[presenter presentViewController:nav animated:YES completion:nil];}
