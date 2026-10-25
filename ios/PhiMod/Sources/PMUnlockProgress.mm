#import "PMUnlockProgress.h"
@interface PMUnlockProgress ()
@property(nonatomic,copy) NSString *path;
@property(nonatomic,copy) NSString *backup;
@property(nonatomic,strong) NSDictionary *states;
@end
@implementation PMUnlockProgress
- (instancetype)initWithRoot:(NSString*)root {
 if((self=[super init])){
  self.path=[root stringByAppendingPathComponent:@"unlock-progress.json"];
  self.backup=[root stringByAppendingPathComponent:@"unlock-progress.backup.json"];
  for(NSString*path in @[self.path,self.backup]){
   NSData*data=[NSData dataWithContentsOfFile:path];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
   if([value isKindOfClass:NSDictionary.class]){self.states=value;break;}
  }
  if(!self.states)self.states=@{};
 }
 return self;
}
- (NSDictionary*)state:(NSString*)identifier rule:(NSDictionary*)rule {
 id state=self.states[identifier];
 return [state isKindOfClass:NSDictionary.class]&&[state[@"signature"] isEqualToString:PMUnlockSignature(rule)]?state:nil;
}
- (BOOL)isOpen:(NSString*)identifier rule:(NSDictionary*)rule {@synchronized(self){return [[self state:identifier rule:rule][@"open"] boolValue];}}
- (BOOL)isSeen:(NSString*)identifier rule:(NSDictionary*)rule {@synchronized(self){return [[self state:identifier rule:rule][@"seen"] boolValue];}}
- (BOOL)commit:(NSDictionary*)next error:(NSError**)error {
 NSData*data=[NSJSONSerialization dataWithJSONObject:next options:NSJSONWritingPrettyPrinted error:error];if(!data)return NO;
 // Back up the last validated in-memory state, not a possibly corrupt disk file.
 NSData*previous=[NSJSONSerialization dataWithJSONObject:self.states options:0 error:error];
 if(!previous||![previous writeToFile:self.backup options:NSDataWritingAtomic error:error]||![data writeToFile:self.path options:NSDataWritingAtomic error:error])return NO;
 self.states=next;return YES;
}
- (BOOL)open:(NSString*)identifier rule:(NSDictionary*)rule error:(NSError**)error {@synchronized(self){
 if([self isOpen:identifier rule:rule])return YES;
 NSMutableDictionary*next=[self.states mutableCopy];next[identifier]=@{@"signature":PMUnlockSignature(rule),@"open":@YES,@"seen":@NO};return [self commit:next error:error];
}}
- (BOOL)seen:(NSString*)identifier signature:(NSString*)signature error:(NSError**)error {@synchronized(self){
 NSDictionary*state=self.states[identifier];if(![state isKindOfClass:NSDictionary.class]||![state[@"signature"] isEqualToString:signature]||![state[@"open"] boolValue])return NO;
 if([state[@"seen"] boolValue])return YES;
 NSMutableDictionary*entry=[state mutableCopy],*next=[self.states mutableCopy];entry[@"seen"]=@YES;next[identifier]=entry;return [self commit:next error:error];
}}
@end
