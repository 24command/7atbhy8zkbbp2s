#import "PMAvatarUI.h"
#import "PMContentStore.h"
#import "PMImageCropController.h"
#import "PMDiagnostics.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@interface PMAvatarPicker:NSObject<UIDocumentPickerDelegate>
@property(nonatomic,weak) UIViewController*presenter;
@end
@implementation PMAvatarPicker
- (void)documentPicker:(UIDocumentPickerViewController*)picker didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls{
 NSURL*url=urls.firstObject;if(!url)return;
 BOOL access=[url startAccessingSecurityScopedResource];UIImage*image=[UIImage imageWithContentsOfFile:url.path];if(access)[url stopAccessingSecurityScopedResource];
 UIViewController*presenter=self.presenter;
 [picker dismissViewControllerAnimated:YES completion:^{
  if(!image){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Avatar" message:@"Cannot decode the selected image." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[presenter presentViewController:a animated:YES completion:nil];return;}
  PMImageCropController*crop=[[PMImageCropController alloc]initWithImage:image aspect:210.0/120.0 completion:^(UIImage*result){
   if(!result)return;NSError*error=nil;NSData*png=UIImagePNGRepresentation(result);
   BOOL ok=png&&[PMContentStore.shared replaceImageData:png identifier:@"pm_avatar" error:&error];
   if(ok){NSUserDefaults*d=NSUserDefaults.standardUserDefaults;[d setBool:YES forKey:@"phimod.avatar.enabled"];[d setObject:NSUUID.UUID.UUIDString forKey:@"phimod.avatar.revision"];PMDiagnosticsWrite("Custom avatar saved and selected");}
   UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Avatar" message:ok?@"\u5934\u50cf\u5df2\u4fdd\u5b58\uff0c\u8fd4\u56de\u9009\u66f2\u6216\u7edf\u8ba1\u9875\u5373\u53ef\u67e5\u770b\u3002":(error.localizedDescription?:@"Avatar save failed") preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[presenter presentViewController:a animated:YES completion:nil];
  }];
  // Crop actions live in navigationItem; a bare modal has no navigation bar.
  UINavigationController*navigation=[[UINavigationController alloc]initWithRootViewController:crop];
  navigation.modalPresentationStyle=UIModalPresentationFullScreen;
  [navigation setNavigationBarHidden:NO animated:NO];
  navigation.navigationBar.tintColor=UIColor.whiteColor;
  UINavigationBarAppearance*appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];
  appearance.backgroundColor=[UIColor colorWithRed:.025 green:.035 blue:.05 alpha:1];
  appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.whiteColor};
  navigation.navigationBar.standardAppearance=appearance;navigation.navigationBar.scrollEdgeAppearance=appearance;navigation.navigationBar.compactAppearance=appearance;
  [presenter presentViewController:navigation animated:YES completion:nil];
 }];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)picker{[picker dismissViewControllerAnimated:YES completion:nil];}
@end
void PMShowAvatarMenu(UIView*source){
 UIViewController*p=source.window.rootViewController;if(!p)return;while(p.presentedViewController)p=p.presentedViewController;
 if([p isKindOfClass:UINavigationController.class])p=((UINavigationController*)p).visibleViewController;
 UIAlertController*a=[UIAlertController alertControllerWithTitle:@"\u81ea\u5b9a\u4e49\u5934\u50cf" message:@"\u4ec5\u66ff\u6362\u672c\u673a\u663e\u793a\u3002" preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"\u5bfc\u5165\u56fe\u7247\u5e76\u88c1\u526a" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){
  static PMAvatarPicker*delegate;delegate=[PMAvatarPicker new];delegate.presenter=p;
  UIDocumentPickerViewController*picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];picker.delegate=delegate;picker.allowsMultipleSelection=NO;[p presentViewController:picker animated:YES completion:nil];
 }]];
 NSString*path=[[PMContentStore.shared asset:@"pm_avatar"]stringByAppendingPathComponent:@"image.png"];
 if([NSFileManager.defaultManager fileExistsAtPath:path])[a addAction:[UIAlertAction actionWithTitle:@"\u4f7f\u7528\u5df2\u5bfc\u5165\u7684\u5934\u50cf" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"phimod.avatar.enabled"];[NSUserDefaults.standardUserDefaults setObject:NSUUID.UUID.UUIDString forKey:@"phimod.avatar.revision"];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u6062\u590d\u539f\u7248\u5934\u50cf" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"phimod.avatar.enabled"];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88" style:UIAlertActionStyleCancel handler:nil]];
 a.popoverPresentationController.sourceView=source;a.popoverPresentationController.sourceRect=CGRectMake(source.bounds.size.width/2,40,1,1);[p presentViewController:a animated:YES completion:nil];
}
