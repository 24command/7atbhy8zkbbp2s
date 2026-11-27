#import "PMNativeOSLoadError.h"
#import <UIKit/UIKit.h>
void PMOSShowLoadError(NSString *message){
 if(!NSThread.isMainThread || !message.length)return;
 static __weak UIAlertController *shown;
 if(shown.presentingViewController)return;
 UIViewController *host=nil;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
  if(scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *window in ((UIWindowScene*)scene).windows){
   if(window.hidden || window.windowLevel!=UIWindowLevelNormal || !window.rootViewController.viewIfLoaded.window)continue;
   host=window.rootViewController;if(window.isKeyWindow)break;
  }
  if(host)break;
 }
 if(!host || host.presentedViewController)return;
 UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"章节 OS 加载提示" message:message preferredStyle:UIAlertControllerStyleAlert];
 [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
 shown=alert;[host presentViewController:alert animated:YES completion:nil];
}