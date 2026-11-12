#import "PMTrashUI.h"
#import "PMContentStore.h"
@interface PMTrashController:UITableViewController
@property(nonatomic,strong)NSArray*entries;
@end
@implementation PMTrashController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"\u56de\u6536\u7ad9";self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];[self refresh];}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)refresh{self.entries=[PMContentStore.shared trashItems];[self.tableView reloadData];UILabel*l=[UILabel new];l.text=@"\u56de\u6536\u7ad9\u4e3a\u7a7a";l.textAlignment=NSTextAlignmentCenter;self.tableView.backgroundView=self.entries.count?nil:l;}
- (NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return self.entries.count;}
- (UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)p{UITableViewCell*c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDictionary*e=self.entries[p.row];c.textLabel.text=e[@"title"];c.textLabel.numberOfLines=2;c.detailTextLabel.text=[e[@"restorable"]boolValue]?@"\u53ef\u6062\u590d\u6216\u6c38\u4e45\u5220\u9664":@"\u65e7\u7248\u56de\u6536\u8d44\u6e90\uff08\u7f3a\u5c11\u5143\u6570\u636e\uff09";return c;}
- (void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)p{[t deselectRowAtIndexPath:p animated:YES];NSDictionary*e=self.entries[p.row];UIAlertController*a=[UIAlertController alertControllerWithTitle:e[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 if([e[@"restorable"]boolValue])[a addAction:[UIAlertAction actionWithTitle:@"\u6062\u590d" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSError*error=nil;if(![PMContentStore.shared restoreTrash:e[@"token"] error:&error])[self message:error.localizedDescription];[self refresh];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u6c38\u4e45\u5220\u9664" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){UIAlertController*c=[UIAlertController alertControllerWithTitle:@"\u786e\u8ba4\u6c38\u4e45\u5220\u9664" message:@"\u5220\u9664\u540e\u65e0\u6cd5\u6062\u590d\u3002" preferredStyle:UIAlertControllerStyleAlert];[c addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];[c addAction:[UIAlertAction actionWithTitle:@"\u5220\u9664" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*y){NSError*error=nil;if(![PMContentStore.shared deleteTrash:e[@"token"] error:&error])[self message:error.localizedDescription];[self refresh];}]];[self presentViewController:c animated:YES completion:nil];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=t;a.popoverPresentationController.sourceRect=[t rectForRowAtIndexPath:p];[self presentViewController:a animated:YES completion:nil];}
- (void)message:(NSString*)text{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u56de\u6536\u7ad9" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end
void PMShowTrash(UIViewController*presenter){PMTrashController*c=[[PMTrashController alloc]initWithStyle:UITableViewStyleInsetGrouped];[presenter presentViewController:[[UINavigationController alloc]initWithRootViewController:c] animated:YES completion:nil];}
