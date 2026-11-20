#pragma once
#import <UIKit/UIKit.h>
#import "PMContentStore.h"
#import "PMDifficultyMetadata.h"
#include "PMUnlockRuntime.hpp"

// A picker is presented from the MOD settings page on the Unity main thread.
@interface PMScorePicker : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,copy) void (^receive)(NSURL *);
@end
@implementation PMScorePicker
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.firstObject && self.receive) self.receive(urls.firstObject);
    self.receive=nil;
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { self.receive=nil; }
@end
namespace pmscores {
using pmbridge::P;
using pmbridge::Runtime;
static void message(UIViewController *parent, NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"自制谱成绩" message:text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [parent presentViewController:alert animated:YES completion:nil];
    });
}
static NSDictionary *library() {
    NSMutableDictionary *songs=[NSMutableDictionary dictionary];
    for (NSDictionary *song in [PMContentStore.shared snapshot][@"songs"]) {
        NSString *identifier=song[@"id"];
        if ([identifier hasPrefix:@"pm_"] && ![song[@"pmOfficial"] boolValue]) songs[identifier]=PMDifficultyRecordLevel(song);
    }
    return songs;
}
static NSDictionary *read(Runtime &r,P game,NSString *identifier,NSString *level) {
    P rec=r.call(game,"GetSongRecord",{"System.String","System.String"},{r.managedString(identifier),r.managedString(level)});
    if (!rec) return @{@"s":@0,@"a":@0,@"c":@0};
    return @{@"s":@(r.get<int>(rec,"s")),@"a":@(r.get<float>(rec,"a")),@"c":@(r.get<int>(rec,"c"))};
}
static bool numeric(id n,double maximum,bool integral) {
    if (![n isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()) return false;
    double v=[n doubleValue];return std::isfinite(v) && v>=0 && v<=maximum && (!integral || std::floor(v)==v);
}
static NSString *restore(Runtime &r, NSURL *url) {
    NSNumber *size=nil; NSError *error=nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:&error] || size.unsignedLongLongValue>16*1024*1024) return @"成绩文件无法读取或超过 16 MiB。";
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    id doc=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]:nil;
    if (![doc isKindOfClass:NSDictionary.class] || ![doc[@"format"] isEqual:@"PhiMod.custom-scores.v1"] || ![doc[@"records"] isKindOfClass:NSArray.class]) return @"请选择 PhiMod 导出的自制谱成绩文件。";
    NSDictionary *songs=library(); NSMutableSet *seen=[NSMutableSet set]; NSMutableArray *matched=[NSMutableArray array];
    for (id row in doc[@"records"]) {
        if (![row isKindOfClass:NSDictionary.class]) return @"记录格式错误。";
        NSString *identifier=row[@"id"],*level=row[@"level"];
        if (![identifier isKindOfClass:NSString.class] || ![level isKindOfClass:NSString.class] || [seen containsObject:identifier] || !numeric(row[@"s"],1000000,true) || !numeric(row[@"a"],100,false) || !numeric(row[@"c"],1,true)) return @"记录重复或数值无效，未导入。";
        [seen addObject:identifier];if ([songs[identifier] isEqual:level]) [matched addObject:row];
    }
    P game=r.mainGame();NSUInteger written=0;
    try {
        for (NSDictionary *row in matched) {
            NSString *identifier=row[@"id"],*level=row[@"level"];
            NSDictionary *current=read(r,game,identifier,level);
            int score=std::max([row[@"s"] intValue],[current[@"s"] intValue]);
            int fc=std::max([row[@"c"] intValue],[current[@"c"] intValue]);
            float acc=std::max([row[@"a"] floatValue],[current[@"a"] floatValue]);
            NSDictionary *merged=@{@"s":@(score),@"a":@(acc),@"c":@(fc)};
            if ([merged isEqual:current]) continue;
            P rec=r.object_new(r.klass("LevelRecord")); r.call(rec,".ctor");r.put(rec,"s",score);r.put(rec,"a",acc);r.put(rec,"c",fc);
            r.call(game,"SetSongRecord",{"System.String","System.String","LevelRecord"},{r.managedString(identifier),r.managedString(level),rec});
            if (![read(r,game,identifier,level) isEqual:merged]) throw std::runtime_error("Record was not saved");
            ++written;
        }
    } catch(const std::exception &e) {
        [PMContentStore.shared scoresChanged];pmunlock::difficultyChanged(r);
        return [NSString stringWithFormat:@"已写入 %lu 首后停止。请检查存档保护或重启后重新导入。\n%s",(unsigned long)written,e.what()];
    }
    if (written) { [PMContentStore.shared scoresChanged];pmunlock::difficultyChanged(r); }
    return [NSString stringWithFormat:@"已更新 %lu 首，保留较好成绩。跳过 %lu 条未匹配的谱面记录。",(unsigned long)written,(unsigned long)(seen.count-matched.count)];
}
static void open(Runtime &r, UIViewController *parent,bool importing) {
    if (!parent || parent.presentedViewController) return;
    static PMScorePicker *delegate=[PMScorePicker new];
    UIDocumentPickerViewController *picker=nil;
    if (importing) {
        picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json"] inMode:UIDocumentPickerModeImport];
        Runtime *runtime=&r;
        delegate.receive=^(NSURL *url){try {message(parent,restore(*runtime,url));} catch(const std::exception &e){message(parent,[NSString stringWithUTF8String:e.what()]);}};
    } else {
        NSDictionary *songs=library();NSMutableArray *records=[NSMutableArray array];P game=r.mainGame();
        for (NSString *identifier in songs) { @autoreleasepool {
            NSDictionary *values=read(r,game,identifier,songs[identifier]);
            if (![values[@"s"] intValue] && ![values[@"a"] floatValue] && ![values[@"c"] intValue]) continue;
            NSMutableDictionary *row=[values mutableCopy];row[@"id"]=identifier;row[@"level"]=songs[identifier];[records addObject:row];
        }}
        NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"format":@"PhiMod.custom-scores.v1",@"records":records} options:0 error:&error];
        NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"PhiMod-custom-scores.json"]];
        if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {message(parent,error.localizedDescription);return;}
        picker=[[UIDocumentPickerViewController alloc] initWithURL:url inMode:UIDocumentPickerModeExportToService];
    }
    picker.delegate=delegate;[parent presentViewController:picker animated:YES completion:nil];
}
}
