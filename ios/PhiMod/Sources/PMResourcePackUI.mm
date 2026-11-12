#import "PMContentStore.h"
#import "PMResourcePackUI.h"
#import "PMDiagnostics.h"
#import "PMArchive.h"
#import "PMSettings.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

@interface UIViewController (PMSkinRefresh)
- (void)reloadPacks;
@end

@interface PMResourcePackPicker : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic) dispatch_queue_t worker;
- (void)showResult:(NSString*)message presenter:(UIViewController*)presenter picker:(UIDocumentPickerViewController*)picker;
@end

@implementation PMResourcePackPicker
- (void)showResult:(NSString*)message presenter:(UIViewController*)presenter picker:(UIDocumentPickerViewController*)picker {
 void(^show)(void)=^{
  if([presenter respondsToSelector:@selector(reloadPacks)])[(id)presenter reloadPacks];
  UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Resource pack" message:message preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  if(presenter)[presenter presentViewController:a animated:YES completion:^{objc_setAssociatedObject(presenter,@selector(PMShowResourcePackPicker),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}];
  else objc_setAssociatedObject(self,@selector(PMShowResourcePackPicker),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 };
 if(picker.presentingViewController)[picker dismissViewControllerAnimated:YES completion:show];else show();
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
 PMDiagnosticsWrite("Resource pack picker cancelled");
 [self showResult:@"Import cancelled." presenter:self.presenter picker:picker];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL*> *)urls {
 UIViewController*presenter=self.presenter;
 if(!urls.count){[self showResult:@"No archive selected." presenter:presenter picker:picker];return;}
 NSURL*source=urls.firstObject;
 NSString*temp=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"zip"]];
 [picker dismissViewControllerAnimated:YES completion:nil];
 dispatch_async(self.worker,^{
  NSError*error=nil;NSFileManager*fm=NSFileManager.defaultManager;
  BOOL access=[source startAccessingSecurityScopedResource];NSNumber*size=nil;
  [source getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
  BOOL ok=[@[@"zip",@"pez"] containsObject:source.pathExtension.lowercaseString]&&size.unsignedLongLongValue>0&&size.unsignedLongLongValue<=128ull*1024*1024;
  if(!ok)error=[NSError errorWithDomain:@"PhiMod.ResourcePack" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Select a ZIP/PEZ archive no larger than 128 MiB."}];
  if(ok)ok=[fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:temp] error:&error];
  if(access)[source stopAccessingSecurityScopedResource];
  NSString*extract=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSArray<NSString*>*files=nil;
  // PMExtractArchive(temp,extract,&error) remains the compatibility entry; packs use the bounded implementation.
  if(ok)files=PMExtractArchiveLimited(temp,extract,512,128ull*1024*1024,32ull*1024*1024,&error);
  if(ok&&!files)ok=NO;
  NSString*destination=nil;BOOL previousEnabled=PMSettingBool("skinEnabled");BOOL settingsChanged=NO;
  // runtime application is gated separately by skinEnabled and the next level lifecycle.
  if(ok){
   NSSet*allowed=[NSSet setWithArray:@[@"line.png",@"judgeline.png",@"click.m4a",@"drag.m4a",@"flick.m4a",@"click.png",@"click_mh.png",@"drag.png",@"drag_mh.png",@"flick.png",@"flick_mh.png",@"hold.png",@"hold_mh.png",@"hit_fx.png",@"info.yml",@"info.yaml",@"click.wav",@"click.ogg",@"click.mp3",@"click.flac",@"drag.wav",@"drag.ogg",@"drag.mp3",@"drag.flac",@"flick.wav",@"flick.ogg",@"flick.mp3",@"flick.flac",@"ending.wav",@"ending.ogg",@"ending.mp3",@"ending.flac"]];
   NSMutableDictionary*selected=[NSMutableDictionary new];unsigned long long total=0;
   for(NSString*path in files){
    NSString*name=path.lastPathComponent.lowercaseString;
    if([name isEqualToString:@"judgeline.png"])name=@"line.png";else if([name isEqualToString:@"tap.png"])name=@"click.png";else if([name isEqualToString:@"tap_mh.png"])name=@"click_mh.png";else if([name isEqualToString:@"hit.png"]||[name isEqualToString:@"hit-fx.png"])name=@"hit_fx.png";
    if(![allowed containsObject:name])continue;
    if(selected[name]){ok=NO;error=[NSError errorWithDomain:@"PhiMod.ResourcePack" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Archive contains duplicate resource names."}];break;}
    NSDictionary*attributes=[fm attributesOfItemAtPath:path error:&error];unsigned long long bytes=[attributes[NSFileSize] unsignedLongLongValue];
    if(!bytes||bytes>32ull*1024*1024||total>128ull*1024*1024-bytes){ok=NO;error=[NSError errorWithDomain:@"PhiMod.ResourcePack" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Expanded resource data exceeds safety limits."}];break;}
    total+=bytes;selected[name]=path;
   }
   for(NSString*required in @[@"click.png",@"drag.png",@"flick.png",@"hold.png"])if(ok&&!selected[required]){ok=NO;error=[NSError errorWithDomain:@"PhiMod.ResourcePack" code:4 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Required resource is missing: %@",required]}];}
   if(ok){
    NSString*documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString*root=[documents stringByAppendingPathComponent:@"PhiMod/resources"];
    if(![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error])ok=NO;
    NSString*name=source.lastPathComponent.length?source.lastPathComponent:@"resource-pack.zip";
    name=[name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
    name=name.stringByDeletingPathExtension;
    destination=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",NSUUID.UUID.UUIDString,name]];
    if(ok)ok=[fm createDirectoryAtPath:destination withIntermediateDirectories:NO attributes:nil error:&error];
    for(NSString*key in selected){if(!ok)break;if(![fm copyItemAtPath:selected[key] toPath:[destination stringByAppendingPathComponent:key] error:&error])ok=NO;}
   }
   if(ok)for(NSString*kind in @[@"click",@"drag",@"flick"]){NSString*out=[destination stringByAppendingPathComponent:[kind stringByAppendingString:@".m4a"]];if([fm fileExistsAtPath:out])continue;
    for(NSString*ext in @[@"wav",@"ogg",@"mp3",@"flac"]){NSString*input=[destination stringByAppendingPathComponent:[kind stringByAppendingFormat:@".%@",ext]];if([fm fileExistsAtPath:input]){ok=PMConvertAudioResource(input,out,&error);break;}}if(!ok)break;
   }
   if(ok)ok=[fm copyItemAtPath:temp toPath:[destination stringByAppendingPathComponent:@"resource-pack.zip"] error:&error];
   if(ok){NSString*settingsError=nil;[[PMSettings shared] setValue:@YES forKey:@"skinEnabled" error:&settingsError];if(settingsError.length){ok=NO;error=[NSError errorWithDomain:@"PhiMod.ResourcePack" code:5 userInfo:@{NSLocalizedDescriptionKey:settingsError}];}else settingsChanged=YES;}
   if(ok){NSString*root=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"PhiMod/resources"];NSString*activePath=[root stringByAppendingPathComponent:@"active.txt"];ok=[destination.lastPathComponent writeToFile:activePath atomically:YES encoding:NSUTF8StringEncoding error:&error];}
   if(!ok){if(settingsChanged){NSString*restoreError=nil;[[PMSettings shared] setValue:@(previousEnabled) forKey:@"skinEnabled" error:&restoreError];}if(destination)[fm removeItemAtPath:destination error:nil];}
  }
  [fm removeItemAtPath:temp error:nil];[fm removeItemAtPath:extract error:nil];
  NSString*message=ok?@"Pack installed and selected. The next chart load will use its note textures.":(error.localizedDescription ?: @"Resource-pack import failed.");
  PMDiagnosticsWrite([NSString stringWithFormat:@"Resource pack import %@: %@",ok?@"ok":@"failed",message].UTF8String);
  dispatch_async(dispatch_get_main_queue(),^{[self showResult:message presenter:presenter picker:picker];});
 });
}
@end

static void PMImportResourcePack(UIView *source){
 UIViewController*presenter=source.window.rootViewController;if(!presenter)return;while(presenter.presentedViewController)presenter=presenter.presentedViewController;
 if([presenter isKindOfClass:UINavigationController.class])presenter=((UINavigationController*)presenter).visibleViewController;
 PMResourcePackPicker*delegate=[PMResourcePackPicker new];delegate.presenter=presenter;delegate.worker=dispatch_queue_create("phimod.resource-pack.import",DISPATCH_QUEUE_SERIAL);
 objc_setAssociatedObject(presenter,@selector(PMShowResourcePackPicker),delegate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 UIDocumentPickerViewController*p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP,UTTypeData] asCopy:YES];p.delegate=delegate;p.allowsMultipleSelection=NO;[presenter presentViewController:p animated:YES completion:nil];
}



@interface PMSkinLibrary : UITableViewController
@property(nonatomic,strong) NSArray* packs;
@property(nonatomic,copy) NSString* root;
@property(nonatomic,copy) NSString* selected;
@property(nonatomic) BOOL enabled;
@end
@implementation PMSkinLibrary
- (void)viewDidLoad {
 [super viewDidLoad];self.title=@"\u97f3\u7b26\u76ae\u80a4";
 self.root=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"PhiMod/resources"];
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importPack)];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self reloadPacks];}
- (void)reloadPacks {
 NSMutableArray*items=[NSMutableArray new];NSFileManager*f=NSFileManager.defaultManager;
 for(NSString*name in [f contentsOfDirectoryAtPath:self.root error:nil]){
  NSString*path=[self.root stringByAppendingPathComponent:name];BOOL dir=NO;
  if(![f fileExistsAtPath:path isDirectory:&dir]||!dir)continue;
  BOOL valid=YES;for(NSString*file in @[@"click.png",@"drag.png",@"flick.png",@"hold.png"])if(![f fileExistsAtPath:[path stringByAppendingPathComponent:file]])valid=NO;
  if(valid)[items addObject:name];
 }
 self.packs=[items sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
 self.selected=[[NSString stringWithContentsOfFile:[self.root stringByAppendingPathComponent:@"active.txt"] encoding:NSUTF8StringEncoding error:nil]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 self.enabled=PMSettingBool("skinEnabled");[self.tableView reloadData];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)importPack {PMImportResourcePack(self.view);}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {return self.packs.count+1;}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {return @"\u9009\u62e9\u540e\u4e0b\u6b21\u8fdb\u5165\u6b4c\u66f2\u751f\u6548\u3002\u70b9\u51fb + \u5bfc\u5165\u65b0\u76ae\u80a4\u3002";}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
 UITableViewCell*cell=[tableView dequeueReusableCellWithIdentifier:@"skin"];
 if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"skin"];
 NSString*name=indexPath.row?self.packs[indexPath.row-1]:nil;NSString*display=name;
 if(name.length>37&&[name characterAtIndex:36]=='-'&&[[NSUUID alloc]initWithUUIDString:[name substringToIndex:36]])display=[name substringFromIndex:37];
 cell.textLabel.text=name?display:@"\u539f\u7248\u6837\u5f0f";cell.detailTextLabel.text=name;
 cell.accessoryType=(!name?!self.enabled:(self.enabled&&[name isEqualToString:self.selected]))?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
 return cell;
}
- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath{return indexPath.row>0;}
- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath*)indexPath{
 if(style!=UITableViewCellEditingStyleDelete||indexPath.row==0)return;NSString*name=self.packs[indexPath.row-1];
 UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u5220\u9664\u76ae\u80a4" message:name preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u5220\u9664" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){
  NSString*base=self.root.stringByResolvingSymlinksInPath,*path=[[base stringByAppendingPathComponent:name]stringByResolvingSymlinksInPath];NSError*error=nil;
  if(![path.stringByDeletingLastPathComponent isEqual:base])return;
  if([name isEqual:self.selected]){NSString*settingsError=nil;if(![[PMSettings shared]setValue:@NO forKey:@"skinEnabled" error:&settingsError])return;[NSFileManager.defaultManager removeItemAtPath:[base stringByAppendingPathComponent:@"active.txt"] error:nil];}
  if(![NSFileManager.defaultManager removeItemAtPath:path error:&error]){UIAlertController*e=[UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];[e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:e animated:YES completion:nil];}[self reloadPacks];
 }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 NSString*name=indexPath.row?self.packs[indexPath.row-1]:nil;
 NSString*path=[self.root stringByAppendingPathComponent:@"active.txt"];
 NSData*previous=[NSData dataWithContentsOfFile:path];NSError*error=nil;NSString*settingsError=nil;BOOL ok=YES;
 if(name){for(NSString*file in @[@"click.png",@"drag.png",@"flick.png",@"hold.png"])if(![NSFileManager.defaultManager fileExistsAtPath:[[self.root stringByAppendingPathComponent:name]stringByAppendingPathComponent:file]])ok=NO;
  if(ok)ok=[name writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
 }
 if(ok){ok=[[PMSettings shared]setValue:@(name!=nil) forKey:@"skinEnabled" error:&settingsError];
  if(!ok&&name){if(previous)[previous writeToFile:path atomically:YES];else[NSFileManager.defaultManager removeItemAtPath:path error:nil];}
 }
 [self reloadPacks];
 NSString*message=ok?@"\u5df2\u9009\u62e9\uff0c\u4e0b\u6b21\u8fdb\u5165\u6b4c\u66f2\u751f\u6548\u3002":(error.localizedDescription?:settingsError?:@"Skin files missing; import the pack again.");
 UIAlertController*a=[UIAlertController alertControllerWithTitle:self.title message:message preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
@end
void PMShowResourcePackPicker(UIView*source){
 UIViewController*presenter=source.window.rootViewController;if(!presenter)return;
 while(presenter.presentedViewController)presenter=presenter.presentedViewController;
 PMSkinLibrary*list=[[PMSkinLibrary alloc]initWithStyle:UITableViewStyleInsetGrouped];
 UINavigationController*nav=[[UINavigationController alloc]initWithRootViewController:list];nav.modalPresentationStyle=UIModalPresentationFormSheet;
 [presenter presentViewController:nav animated:YES completion:nil];
}
