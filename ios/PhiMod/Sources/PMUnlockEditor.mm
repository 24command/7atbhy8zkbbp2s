#import "PMUnlockEditor.h"
#import "PMContentStore.h"
#import "PMUnlockRules.h"
#include "PMContentRuntime.hpp"
@interface PMUnlockReferencePicker:UITableViewController<UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSDictionary*>*choices;
@property(nonatomic,strong) NSArray<NSDictionary*>*filtered;
@property(nonatomic,strong) UISearchController*search;
@property(nonatomic,copy) void(^selected)(NSDictionary*);
@end
@implementation PMUnlockReferencePicker
- (void)viewDidLoad{
 [super viewDidLoad];self.filtered=self.choices;
 self.search=[[UISearchController alloc]initWithSearchResultsController:nil];self.search.searchResultsUpdater=self;self.search.obscuresBackgroundDuringPresentation=NO;
 self.search.searchBar.placeholder=@"\u641c\u7d22\u66f2\u540d / \u7ae0\u8282\u540d / ID";
 self.navigationItem.searchController=self.search;self.navigationItem.hidesSearchBarWhenScrolling=NO;self.definesPresentationContext=YES;
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}
- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)updateSearchResultsForSearchController:(UISearchController*)search{
 NSString*q=[search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 self.filtered=q.length?[self.choices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary*entry,NSDictionary*bindings){
  for(NSString*key in @[@"title",@"id"]){NSString*text=entry[key];if([text rangeOfString:q options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound)return YES;}return NO;
 }]]:self.choices;[self.tableView reloadData];
 UILabel*empty=[[UILabel alloc]initWithFrame:self.tableView.bounds];empty.text=@"\u6ca1\u6709\u5339\u914d\u7ed3\u679c";empty.textAlignment=NSTextAlignmentCenter;self.tableView.backgroundView=self.filtered.count?nil:empty;
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section{return self.filtered.count;}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)index{
 UITableViewCell*cell=[table dequeueReusableCellWithIdentifier:@"reference"];
 if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"reference"];
 NSDictionary*entry=self.filtered[index.row];cell.textLabel.text=entry[@"title"];cell.detailTextLabel.text=entry[@"id"];cell.textLabel.numberOfLines=2;return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)index{
 NSDictionary*entry=self.filtered[index.row];void(^completion)(NSDictionary*)=self.selected;self.selected=nil;
 // Dismiss the containing picker navigation controller, not UISearchController.
 UIViewController*container=self.navigationController?:self;UIViewController*presenter=container.presentingViewController;
 [self.search.searchBar resignFirstResponder];self.search.active=NO;
 [presenter dismissViewControllerAnimated:YES completion:^{if(completion)completion(entry);}];
}
@end
@interface PMUnlockEditor : UITableViewController
@property(nonatomic,copy) NSString*identifier;
@property(nonatomic,strong) NSMutableDictionary*rule;
@property(nonatomic,strong) NSMutableArray*conditions;
@end
@implementation PMUnlockEditor
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"\u89e3\u9501\u6761\u4ef6";
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
}
- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)message:(NSString*)text{UIAlertController*a=[UIAlertController alertControllerWithTitle:self.title message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return self.conditions.count+3;}
- (NSString*)tableView:(UITableView*)t titleForFooterInSection:(NSInteger)s{return @"\u4fdd\u5b58\u540e\u8fd4\u56de\u8c31\u5e93\u70b9\u51fb\u5e94\u7528\u5230\u6e38\u620f\u3002\u6761\u4ef6\u4f7f\u7528\u6b63\u5e38\u8ba1\u5206\u6210\u7ee9\uff1b\u5df2\u5bfc\u5165\u7684\u89e3\u9501\u52a8\u753b\u4e0e\u8fde\u6253\u914d\u7f6e\u4f1a\u4fdd\u7559\u3002";}
- (UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)p{
 UITableViewCell*c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 if(p.row==0){c.textLabel.text=@"\u542f\u7528\u89e3\u9501\u6761\u4ef6";c.accessoryType=[self.rule[@"enabled"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
 else if(p.row==1)c.textLabel.text=[self.rule[@"mode"] isEqual:@"any"]?@"\u6ee1\u8db3\u4efb\u4e00\u6761\u4ef6":@"\u5168\u90e8\u6761\u4ef6\u6ee1\u8db3";
 else if(p.row==2)c.textLabel.text=@"+ \u6dfb\u52a0\u6761\u4ef6";
 else{NSDictionary*d=self.conditions[p.row-3];c.textLabel.text=[NSString stringWithFormat:@"%@  %@",d[@"type"],d[@"value"]?:@""];c.detailTextLabel.text=[NSString stringWithFormat:@"%@  slot=%@",d[@"ref"]?:@"RKS",d[@"slot"]?:@(-1)];}
 return c;
}
- (void)presentMenu:(UIAlertController*)a{[a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,80,1,1);[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)p{
 [t deselectRowAtIndexPath:p animated:YES];
 if(p.row==0){self.rule[@"enabled"]=@(![self.rule[@"enabled"] boolValue]);[t reloadData];return;}
 if(p.row==1){self.rule[@"mode"]=[self.rule[@"mode"] isEqual:@"any"]?@"all":@"any";[t reloadData];return;}
 if(p.row==2){if(self.conditions.count>=64){[self message:@"Maximum 64 conditions"];return;}
 UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u6761\u4ef6\u7c7b\u578b" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 for(NSString*type in @[@"score",@"acc",@"fc",@"phi",@"rks",@"chapter"])[a addAction:[UIAlertAction actionWithTitle:type style:UIAlertActionStyleDefault handler:^(UIAlertAction*action){NSMutableDictionary*c=[@{@"type":type,@"slot":@(-1)} mutableCopy];if([type isEqual:@"score"])c[@"value"]=@700000;else if([type isEqual:@"acc"])c[@"value"]=@95;else if([type isEqual:@"rks"])c[@"value"]=@10;[self chooseReference:c index:-1];}]];
 [self presentMenu:a];return;}
 NSInteger index=p.row-3;NSMutableDictionary*c=[self.conditions[index] mutableCopy];
 UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u7f16\u8f91\u6761\u4ef6" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"\u9009\u62e9\u5f15\u7528 / \u4fee\u6539\u6761\u4ef6" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self chooseReference:c index:index];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u5220\u9664" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){[self.conditions removeObjectAtIndex:index];[self.tableView reloadData];}]];[self presentMenu:a];
}
- (void)chooseReference:(NSMutableDictionary*)c index:(NSInteger)index{
 if([c[@"type"] isEqual:@"rks"]){[self threshold:c index:index];return;}
 BOOL chapter=[c[@"type"] isEqual:@"chapter"];NSDictionary*db=[PMContentStore.shared snapshot];NSMutableArray*choices=[NSMutableArray new];
 for(NSDictionary*e in db[chapter?@"chapters":@"songs"]){if([e[@"id"] isEqual:self.identifier])continue;[choices addObject:@{@"id":e[@"id"],@"title":e[chapter?@"name":@"title"]?:e[@"id"]}];}
 NSDictionary*official=pmcontent::cachedOfficialSnapshot();
 if(chapter){for(NSDictionary*e in official[@"chapters"])[choices addObject:@{@"id":e[@"chapterCode"],@"title":e[@"songInfo"][@"title"]?:e[@"chapterCode"]}];}
 else for(NSString*k in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSDictionary*e in official[@"songBase"][k])[choices addObject:@{@"id":e[@"songsId"],@"title":e[@"songsName"]?:e[@"songsId"]}];
 if(!choices.count){[self message:@"No available dependencies. Import songs/chapters first."];return;}
 PMUnlockReferencePicker*picker=[[PMUnlockReferencePicker alloc]initWithStyle:UITableViewStylePlain];picker.choices=choices;
 picker.title=chapter?@"\u9009\u62e9\u7ae0\u8282":@"\u9009\u62e9\u6b4c\u66f2";
 __weak PMUnlockEditor*weak=self;
 picker.selected=^(NSDictionary*entry){c[@"ref"]=entry[@"id"];[weak threshold:c index:index];};
 UINavigationController*nav=[[UINavigationController alloc]initWithRootViewController:picker];nav.modalPresentationStyle=UIModalPresentationFormSheet;[self presentViewController:nav animated:YES completion:nil];
}
- (void)threshold:(NSMutableDictionary*)c index:(NSInteger)index{
 BOOL value=[@[@"score",@"acc",@"rks"] containsObject:c[@"type"]];BOOL slot=![c[@"type"] isEqual:@"rks"];
 UIAlertController*a=[UIAlertController alertControllerWithTitle:c[@"type"] message:@"Difficulty: -1=any, 0=EZ, 1=HD, 2=IN, 3=AT. Chapter: every song >=700000." preferredStyle:UIAlertControllerStyleAlert];
 if(value)[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Threshold";f.text=[c[@"value"] description];f.keyboardType=UIKeyboardTypeDecimalPad;}];
 if(slot)[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Difficulty (-1 to 3)";f.text=[c[@"slot"] description]?:@"-1";f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;}];
 [a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u786e\u5b9a" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSUInteger i=0;if(value)c[@"value"]=a.textFields[i++].text;if(slot)c[@"slot"]=a.textFields[i].text;
 id normalized=PMNormalizeUnlockRule(@{@"enabled":@YES,@"conditions":@[c]});NSString*error=PMUnlockValidationError(normalized);if(error){[self message:error];return;}
 id condition=normalized[@"conditions"][0];if(slot){double difficulty=[condition[@"slot"] doubleValue];if(difficulty!=floor(difficulty)){[self message:@"Difficulty must be an integer (-1 to 3)."];return;}}if(index<0)[self.conditions addObject:condition];else self.conditions[index]=condition;[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)save{
 self.rule[@"conditions"]=self.conditions;NSString*invalid=PMUnlockValidationError(self.rule);if(invalid){[self message:invalid];return;}
 NSDictionary*current=[PMContentStore.shared snapshot];NSMutableDictionary*db=[current mutableCopy];BOOL found=NO;
 for(NSString*key in @[@"songs",@"chapters"]){NSMutableArray*items=[current[key] mutableCopy];for(NSUInteger i=0;i<items.count;++i)if([items[i][@"id"] isEqual:self.identifier]){NSMutableDictionary*entity=[items[i] mutableCopy];entity[@"unlock"]=[self.rule copy];[entity removeObjectForKey:@"unlockProgress"];items[i]=entity;found=YES;}db[key]=items;}
 if(!found){[self message:@"Entity was deleted; changes not saved."];return;}
 NSError*error=nil;if(![PMContentStore.shared commit:db error:&error]){[self message:error.localizedDescription];return;}[self dismissViewControllerAnimated:YES completion:nil];
}
@end
void PMShowUnlockEditor(UIViewController*presenter,NSString*identifier){
 NSDictionary*entity=nil;NSDictionary*db=[PMContentStore.shared snapshot];for(NSString*k in @[@"songs",@"chapters"])for(NSDictionary*e in db[k])if([e[@"id"] isEqual:identifier])entity=e;if(!entity)return;
 id rule=PMNormalizeUnlockRule(entity[@"unlock"]);PMUnlockEditor*editor=[[PMUnlockEditor alloc]initWithStyle:UITableViewStyleInsetGrouped];editor.identifier=identifier;editor.rule=[rule isKindOfClass:NSDictionary.class]?[rule mutableCopy]:[NSMutableDictionary new];editor.conditions=[editor.rule[@"conditions"] isKindOfClass:NSArray.class]?[editor.rule[@"conditions"] mutableCopy]:[NSMutableArray new];
 UINavigationController*nav=[[UINavigationController alloc]initWithRootViewController:editor];nav.modalPresentationStyle=UIModalPresentationFormSheet;[presenter presentViewController:nav animated:YES completion:nil];
}
