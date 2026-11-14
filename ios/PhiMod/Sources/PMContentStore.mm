#import "PMDifficultyMetadata.h"
#import "PMDiagnostics.h"
#import "PMCoverImage.h"
#import "PMContentStore.h"
#import "PMChapterEditing.h"
#import "PMChartConvert.h"
#import "PMExtensionTracks.h"
#import "PMArchive.h"
#import "PMFileDigest.h"
#import "PMUnlockRules.h"
#include "PMContentRuntime.hpp"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include "../Core/PMPCMImport.hpp"
#include "../Core/PMAudioFileType.hpp"
#include <functional>
#define STB_VORBIS_HEADER_ONLY
#include "../Vendor/stb/stb_vorbis.c"
namespace {
NSError*err(NSString*s){return [NSError errorWithDomain:@"PhiMod.Library" code:1 userInfo:@{NSLocalizedDescriptionKey:s ?: @"操作失败"}];}
id clone(id x){NSData*d=[NSJSONSerialization dataWithJSONObject:x options:0 error:nil];return d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;}
BOOL writeJSON(id x,NSString*p,NSError**e){NSData*d=[NSJSONSerialization dataWithJSONObject:x options:NSJSONWritingPrettyPrinted error:e];return d&&[d writeToFile:p options:NSDataWritingAtomic error:e];}
BOOL writeJSONCompact(id x,NSString*p,NSError**e){NSData*d=[NSJSONSerialization dataWithJSONObject:x options:0 error:e];return d&&[d writeToFile:p options:NSDataWritingAtomic error:e];}
NSString*fresh(){return [@"pm_" stringByAppendingString:[[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString]];}
BOOL safeID(NSString*x){if(![x isKindOfClass:NSString.class]||![x hasPrefix:@"pm_"]||x.length<=3||[x lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>96)return NO;NSCharacterSet*letters=[NSCharacterSet alphanumericCharacterSet];for(NSUInteger i=3;i<x.length;i++){unichar c=[x characterAtIndex:i];if(c!='_'&&! [letters characterIsMember:c])return NO;}return YES;}
// IDs remain compatible with safeID and existing on-disk references.
NSString*songIDPart(id raw,NSString*fallback,NSUInteger budget){
 NSString*value=[raw isKindOfClass:NSString.class]?[raw precomposedStringWithCanonicalMapping]:@"";
 NSMutableString*out=[NSMutableString new];NSCharacterSet*letters=NSCharacterSet.alphanumericCharacterSet;
 for(NSUInteger i=0;i<value.length;++i){unichar c=[value characterAtIndex:i];
  NSString*piece=(c=='_'||[letters characterIsMember:c])?[NSString stringWithCharacters:&c length:1]:@"_";
  if([piece isEqualToString:@"_"]&&(!out.length||[out hasSuffix:@"_"]))continue;
  if([out lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+[piece lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>budget)break;
  [out appendString:piece];
 }
 while([out hasSuffix:@"_"])[out deleteCharactersInRange:NSMakeRange(out.length-1,1)];
 return out.length?out:fallback;
}
NSMutableSet*reservedSongIDs(PMContentStore*store){
 NSMutableSet*used=[NSMutableSet new];NSDictionary*db=[store snapshot];
 for(NSString*key in @[@"songs",@"chapters"])for(NSDictionary*entry in db[key])if([entry[@"id"]isKindOfClass:NSString.class])[used addObject:[entry[@"id"]lowercaseString]];
 for(NSString*name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[store.root stringByAppendingPathComponent:@"assets"] error:nil])[used addObject:name.lowercaseString];
 return used;
}
NSString*readableSongID(id title,id charter,id level,NSMutableSet*used){
 // Reserve room for the prefix, separators and a collision suffix (96 bytes maximum).
 NSString*base=[NSString stringWithFormat:@"pm_%@_%@_%@",songIDPart(title,@"Untitled",42),songIDPart(charter,@"Unknown",24),songIDPart(level,@"IN",12)];
 NSString*identifier=base;NSUInteger suffix=2;
 while([used containsObject:identifier.lowercaseString])identifier=[base stringByAppendingFormat:@"_%lu",(unsigned long)suffix++];
 [used addObject:identifier.lowercaseString];return identifier;
}
void recoverChapterImports(NSString*root,NSDictionary*db){
 NSFileManager*f=NSFileManager.defaultManager;NSString*directory=[root stringByAppendingPathComponent:@"import-journals"];
 NSMutableSet*live=[NSMutableSet new];for(NSString*key in @[@"songs",@"chapters"])for(NSDictionary*entity in db[key])if(entity[@"id"])[live addObject:entity[@"id"]];
 for(NSString*name in [f contentsOfDirectoryAtPath:directory error:nil]){
  if(![name.pathExtension isEqualToString:@"json"])continue;NSString*path=[directory stringByAppendingPathComponent:name];NSData*data=[NSData dataWithContentsOfFile:path];id journal=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
  if(![journal isKindOfClass:NSDictionary.class]||![journal[@"ids"] isKindOfClass:NSArray.class])continue;
  BOOL valid=YES;for(id identifier in journal[@"ids"])if(!safeID(identifier)){valid=NO;break;}if(!valid)continue;
  BOOL cleaned=YES;for(NSString*identifier in journal[@"ids"])if(![live containsObject:identifier]){NSString*asset=[[root stringByAppendingPathComponent:@"assets"] stringByAppendingPathComponent:identifier];if([f fileExistsAtPath:asset]&&![f removeItemAtPath:asset error:nil])cleaned=NO;}
  if(cleaned)[f removeItemAtPath:path error:nil];
 }
}
NSString*text(NSString*p){return [[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]stringByReplacingOccurrencesOfString:@"\ufeff" withString:@""] ?: @"";}
NSArray*csv(NSString*s){NSMutableArray*rows=[NSMutableArray new],*row=[NSMutableArray new];NSMutableString*value=[NSMutableString new];BOOL quoted=NO;for(NSUInteger i=0;i<s.length;++i){unichar c=[s characterAtIndex:i];if(c=='"'){if(quoted&&i+1<s.length&&[s characterAtIndex:i+1]=='"'){[value appendString:@"\""];++i;}else quoted=!quoted;}else if(c==','&&!quoted){[row addObject:[value copy]];[value setString:@""];}else if((c=='\n'||c=='\r')&&!quoted){if(c=='\r'&&i+1<s.length&&[s characterAtIndex:i+1]=='\n')++i;[row addObject:[value copy]];[rows addObject:row];row=[NSMutableArray new];[value setString:@""];}else[value appendFormat:@"%C",c];}if(value.length||row.count){[row addObject:value];[rows addObject:row];}return rows;}
NSString*locate(NSArray*files,NSString*name,NSArray*extensions,BOOL optional,NSError**e){NSMutableArray*candidates=[NSMutableArray new];for(NSString*p in files)if([extensions containsObject:p.pathExtension.lowercaseString]){NSString*base=p.lastPathComponent.lowercaseString;if([@[@"info.json",@"extra.json",@"chapter.json",@"metadata.json",@"conversion.json",@"source-audio.json",@"shader-compatibility-ios.json",@"shader-render-stages-ios.json",@"chart-native.json"]containsObject:base])continue;if(name.length&&[base caseInsensitiveCompare:name.lastPathComponent.lowercaseString]==NSOrderedSame)return p;[candidates addObject:p];}if(!name.length){for(NSString*preferred in @[@"audio.pcm",@"music.m4a",@"audio.export.m4a",@"audio.source.mp3",@"audio.source.ogg",@"audio.source.wav",@"audio.source.flac",@"source.rpe.json",@"source.pec",@"chart.json"]){for(NSString*p in candidates)if([p.lastPathComponent.lowercaseString isEqualToString:preferred])return p;}}if(candidates.count==1)return candidates[0];if(!candidates.count&&optional)return nil;if(e)*e=err(candidates.count?@"Multiple chart or audio candidates; specify a path in info.yml/info.csv":@"Chart package is missing a chart or audio file");return nil;}
NSString*sourceChartFor(NSArray*files,NSDictionary*chart,NSString*fallback){NSString*format=chart[@"pmFormat"],*dir=fallback.stringByDeletingLastPathComponent;NSMutableArray*local=[NSMutableArray new];for(NSString*p in files)if([p.stringByDeletingLastPathComponent isEqualToString:dir])[local addObject:p];NSArray*pool=local.count?local:files;if([format isEqualToString:@"PEC"]){for(NSString*p in pool)if([p.pathExtension.lowercaseString isEqualToString:@"pec"])return p;}if([format isEqualToString:@"RPE"]){for(NSString*p in pool)if([p.lastPathComponent.lowercaseString hasSuffix:@".rpe.json"])return p;}return fallback;}
NSString*digest(NSString*p){return PMFileSHA256(p); }
// Compact AAC settings. Keeps `music.m4a` around 2-3 MB for a 3-minute
// track instead of ~30 MB PCM CAF, and AVAudioFile decodes it transparently
// in PMContentRuntime without any format-specific handling.
NSDictionary*compactAudioSettings(double rate,int channels){
 if(!std::isfinite(rate)||rate<8000)rate=44100;
 if(rate>48000)rate=48000;
 if(channels<1||channels>8)channels=2;
 return @{AVFormatIDKey:@(kAudioFormatMPEG4AAC),AVSampleRateKey:@(rate),AVNumberOfChannelsKey:@(channels),AVEncoderBitRateKey:@(128000),AVEncoderAudioQualityKey:@(AVAudioQualityHigh)};
}
BOOL decodeAudio(NSString*source,NSString*destination,NSError**error){
 NSURL*url=[NSURL fileURLWithPath:source];NSError*openError=nil;AVAudioFile*input=[[AVAudioFile alloc]initForReading:url error:&openError];
 if(!input&&[source.pathExtension.lowercaseString isEqualToString:@"pcm"]){
  NSString*temporary=[destination.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@"pcm-import-%@.wav",NSUUID.UUID.UUIDString]];
  @try{try{pmpcm::toWav(source.fileSystemRepresentation,temporary.fileSystemRepresentation);return decodeAudio(temporary,destination,error);}catch(const std::exception&e){if(error)*error=err([NSString stringWithUTF8String:e.what()]);return NO;}}
  @finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
 }
 if(!input&&error)*error=openError;
 if(input){
  AVAudioFormat*srcFormat=input.processingFormat;
  NSDictionary*settings=compactAudioSettings(srcFormat.sampleRate,srcFormat.channelCount);
  AVAudioFile*out=[[AVAudioFile alloc]initForWriting:[NSURL fileURLWithPath:destination] settings:settings commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:error];
  if(!out)return NO;
  AVAudioPCMBuffer*buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:srcFormat frameCapacity:65536];
  if(!buffer){if(error)*error=err(@"音频缓冲区分配失败");return NO;}
  if(srcFormat.sampleRate!=out.processingFormat.sampleRate||srcFormat.channelCount!=out.processingFormat.channelCount){
   AVAudioConverter*converter=[[AVAudioConverter alloc]initFromFormat:srcFormat toFormat:out.processingFormat];if(!converter){if(error)*error=err(@"Audio sample-rate conversion unavailable");return NO;}
   AVAudioPCMBuffer*converted=[[AVAudioPCMBuffer alloc]initWithPCMFormat:out.processingFormat frameCapacity:65536];if(!converted){if(error)*error=err(@"Audio output buffer allocation failed");return NO;}
   __block NSError*readFailure=nil;
   for(;;){AVAudioConverterOutputStatus status=[converter convertToBuffer:converted error:error withInputFromBlock:^AVAudioBuffer*(AVAudioPacketCount requested,AVAudioConverterInputStatus*inputStatus){
    if(input.framePosition>=input.length){*inputStatus=AVAudioConverterInputStatus_EndOfStream;return nil;}
    if(![input readIntoBuffer:buffer frameCount:MIN(requested,buffer.frameCapacity) error:&readFailure]){*inputStatus=AVAudioConverterInputStatus_EndOfStream;return nil;}
    *inputStatus=buffer.frameLength?AVAudioConverterInputStatus_HaveData:AVAudioConverterInputStatus_EndOfStream;return buffer.frameLength?buffer:nil;
   }];if(readFailure){if(error)*error=readFailure;return NO;}if(status==AVAudioConverterOutputStatus_Error)return NO;
    if(converted.frameLength&&![out writeFromBuffer:converted error:error])return NO;if(status==AVAudioConverterOutputStatus_EndOfStream)break;
   }
  }else while(input.framePosition<input.length){
   if(![input readIntoBuffer:buffer frameCount:65536 error:error])return NO;
   if(buffer.frameLength==0)break;
   if(![out writeFromBuffer:buffer error:error])return NO;
  }
  return YES;
 }
 if(![source.pathExtension.lowercaseString isEqualToString:@"ogg"])return NO;if(error)*error=nil;
 int code=0;stb_vorbis*v=stb_vorbis_open_filename(source.fileSystemRepresentation,&code,nullptr);if(!v){if(error)*error=err(@"音乐解码失败（支持 WAV/MP3/M4A/FLAC/Ogg Vorbis）");return NO;}stb_vorbis_info info=stb_vorbis_get_info(v);if(info.channels<1||info.channels>8||info.sample_rate==0||info.sample_rate>192000){stb_vorbis_close(v);if(error)*error=err(@"音频声道或采样率不支持");return NO;}
  NSString*pcm=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"phimod-vorbis-%@.caf",NSUUID.UUID.UUIDString]];
  BOOL ok=NO;
  @try{
   AVAudioFormat*format=[[AVAudioFormat alloc]initStandardFormatWithSampleRate:info.sample_rate channels:info.channels];
   AVAudioFile*out=[[AVAudioFile alloc]initForWriting:[NSURL fileURLWithPath:pcm] settings:format.settings commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:error];
   if(!out)return NO;
   AVAudioPCMBuffer*buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:format frameCapacity:65536];
   if(!buffer){if(error)*error=err(@"Audio buffer allocation failed");return NO;}
   uint64_t frames=0;
   for(;;){int n=stb_vorbis_get_samples_float(v,info.channels,(float**)(void*)buffer.floatChannelData,65536);
    if(n<=0)break;buffer.frameLength=n;frames+=n;if(![out writeFromBuffer:buffer error:error])return NO;
   }
   int decodeError=stb_vorbis_get_error(v);
   if(!frames||decodeError){if(error)*error=err([NSString stringWithFormat:@"Vorbis decode failed (code %d, frames %llu)",decodeError,(unsigned long long)frames]);return NO;}
   out=nil; // Finalize CAF before opening it through the shared AAC/resampler path.
   ok=decodeAudio(pcm,destination,error);
  }@finally{stb_vorbis_close(v);[NSFileManager.defaultManager removeItemAtPath:pcm error:nil];}
  return ok;
}
BOOL audio(NSString*source,NSString*destination,NSError**error){
 // Packs frequently label WAV/MP3 bytes as .ogg. Probe bounded header bytes,
 // then give Apple's decoder the correct suffix without changing the original.
 unsigned char header[64]={};size_t count=0;FILE*file=fopen(source.fileSystemRepresentation,"rb");
 if(file){count=fread(header,1,sizeof(header),file);fclose(file);}
 NSString*detected=[NSString stringWithUTF8String:phimod::audioFileExtension(header,count)];
 NSString*temporary=nil,*decodeSource=source;NSError*failure=nil;BOOL ok=NO;
 @try{
  if(detected.length&&![detected isEqualToString:source.pathExtension.lowercaseString]){
   temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"phimod-audio-%@.%@",NSUUID.UUID.UUIDString,detected]];
   if(![NSFileManager.defaultManager copyItemAtPath:source toPath:temporary error:&failure]){if(error)*error=failure;return NO;}
   decodeSource=temporary;
   PMDiagnosticsWrite([NSString stringWithFormat:@"Audio format corrected: %@ -> %@",source.lastPathComponent,detected].UTF8String);
  }
  ok=decodeAudio(decodeSource,destination,&failure);
 }@finally{if(temporary)[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
 if(!ok){
  NSString*message=[NSString stringWithFormat:@"Audio conversion failed: %@ (detected %@): %@",source.lastPathComponent,detected.length?detected:@"unknown",failure.localizedDescription?:@"Decoder returned no audio"];
  PMDiagnosticsWrite(message.UTF8String);
  if(error)*error=[NSError errorWithDomain:@"PhiMod.Audio" code:1 userInfo:failure?@{NSLocalizedDescriptionKey:message,NSUnderlyingErrorKey:failure}:@{NSLocalizedDescriptionKey:message}];
 }else if(error)*error=nil;
 return ok;
}
}

BOOL PMConvertAudioResource(NSString*source,NSString*destination,NSError**error){return audio(source,destination,error);}
NSArray*storeArray(id x){return [x isKindOfClass:NSArray.class]?x:@[];}
BOOL writeText(NSString*value,NSString*p,NSError**e){NSData*d=[value dataUsingEncoding:NSUTF8StringEncoding];return d&&[d writeToFile:p options:NSDataWritingAtomic error:e];}
NSString*androidFormat(NSDictionary*chart){NSString*f=chart[@"pmFormat"];return [f isKindOfClass:NSString.class]&&f.length?f:@"Phigros v3";}
NSString*hexUTF8(NSString*x){NSData*d=[x dataUsingEncoding:NSUTF8StringEncoding];const unsigned char*b=(const unsigned char*)d.bytes;NSMutableString*out=[NSMutableString new];for(NSUInteger i=0;i<d.length;i++)[out appendFormat:@"%02x",b[i]];return out.length?out:@"-";}
NSUInteger noteCount(NSDictionary*chart,BOOL fake){NSUInteger n=0;for(NSDictionary*l in storeArray(chart[@"judgeLineList"]))for(NSString*side in @[@"notesAbove",@"notesBelow"])for(NSDictionary*x in storeArray(l[side]))if([x[@"pmFake"]boolValue]==fake)++n;return n;}
BOOL writeConversionMetadata(NSDictionary*chart,NSString*folder,NSError**e){NSArray*w=[chart[@"pmWarnings"]isKindOfClass:NSArray.class]?chart[@"pmWarnings"]:@[];NSUInteger real=chart[@"pmRealNotes"]?[chart[@"pmRealNotes"]unsignedIntegerValue]:noteCount(chart,NO),fake=chart[@"pmFakeNotes"]?[chart[@"pmFakeNotes"]unsignedIntegerValue]:noteCount(chart,YES);NSDictionary*v=@{@"version":@15,@"warnings":w,@"realNotes":@(real),@"fakeNotes":@(fake)};return writeJSONCompact(v,[folder stringByAppendingPathComponent:@"conversion.json"],e);}
BOOL writeSourceAudio(NSString*source,NSString*folder,NSError**e){if(!source.length||![NSFileManager.defaultManager fileExistsAtPath:source])return YES;AVAudioFile*input=[[AVAudioFile alloc]initForReading:[NSURL fileURLWithPath:source] error:nil];if(!input)return YES;NSString*ext=source.pathExtension.lowercaseString;if(![@[@"mp3",@"ogg",@"wav",@"flac"]containsObject:ext])return YES;NSString*name=[NSString stringWithFormat:@"audio.source.%@",ext],*dest=[folder stringByAppendingPathComponent:name];if(![source isEqualToString:dest]&&![[NSFileManager defaultManager]fileExistsAtPath:dest]&&![[NSFileManager defaultManager]copyItemAtPath:source toPath:dest error:e])return NO;NSDictionary*attrs=[[NSFileManager defaultManager]attributesOfItemAtPath:dest error:nil];NSNumber*bytes=attrs[NSFileSize]?:@0;NSDictionary*meta=@{@"extension":ext,@"rate":@((NSInteger)llround(input.processingFormat.sampleRate)),@"channels":@(input.processingFormat.channelCount),@"frames":@(input.length),@"format":@"encoded-audio-v1",@"file":name,@"bytes":bytes};return writeJSONCompact(meta,[folder stringByAppendingPathComponent:@"source-audio.json"],e);}
void appendDecorExtras(NSMutableString*out,NSDictionary*decor,NSUInteger li){
 NSArray*controlNames=@[@"alphaControl",@"sizeControl",@"posControl",@"yControl"];
 for(NSUInteger channel=0;channel<controlNames.count;channel++){NSArray*points=storeArray(decor[controlNames[channel]]);if(!points.count)continue;NSMutableArray*sorted=[points mutableCopy];[sorted sortUsingComparator:^NSComparisonResult(id a,id b){double x=[a[@"x"]doubleValue],y=[b[@"x"]doubleValue];return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];if(sorted.count==1){NSDictionary*q=sorted[0];NSString*key=[controlNames[channel]substringToIndex:[controlNames[channel]length]-7];double value=q[key]?[q[key]doubleValue]:1;[out appendFormat:@"C %lu %lu %.17g %.17g %.17g %.17g\n",(unsigned long)li,(unsigned long)channel,[q[@"x"]doubleValue],[q[@"x"]doubleValue],value,value];}else for(NSUInteger i=1;i<sorted.count;i++){NSDictionary*a=sorted[i-1],*b=sorted[i];NSString*key=[controlNames[channel]substringToIndex:[controlNames[channel]length]-7];double va=a[key]?[a[key]doubleValue]:1,vb=b[key]?[b[key]doubleValue]:1;[out appendFormat:@"C %lu %lu %.17g %.17g %.17g %.17g\n",(unsigned long)li,(unsigned long)channel,[a[@"x"]doubleValue],[b[@"x"]doubleValue],va,vb];}}
 NSArray*scalarNames=@[@"scaleXEvents",@"scaleYEvents",@"inclineEvents"];int scalarChannels[]={0,1,6};for(NSUInteger k=0;k<scalarNames.count;k++)for(NSDictionary*e in storeArray(decor[scalarNames[k]]))[out appendFormat:@"L %lu %d %.17g %.17g %.17g %.17g\n",(unsigned long)li,scalarChannels[k],[e[@"startTime"]doubleValue],[e[@"endTime"]doubleValue],[e[@"start"]doubleValue],[e[@"end"]doubleValue]];
 for(NSDictionary*e in storeArray(decor[@"colorEvents"])){NSArray*a=storeArray(e[@"start"]),*b=storeArray(e[@"end"]);for(int channel=0;channel<3;channel++)if(channel<(int)a.count&&channel<(int)b.count)[out appendFormat:@"L %lu %d %.17g %.17g %.17g %.17g\n",(unsigned long)li,channel+2,[e[@"startTime"]doubleValue],[e[@"endTime"]doubleValue],[a[channel]doubleValue]/255.,[b[channel]doubleValue]/255.];}
 for(NSUInteger index=0;index<storeArray(decor[@"textEvents"]).count;index++){NSDictionary*e=storeArray(decor[@"textEvents"])[index];[out appendFormat:@"T %lu %.17g %.17g %@ %@\n",(unsigned long)li,[e[@"startTime"]doubleValue],[e[@"endTime"]doubleValue],hexUTF8(e[@"start"]?:@""),hexUTF8(e[@"end"]?:@"")];}
}
BOOL writeExtras(NSDictionary*chart,NSString*folder,NSError**e){NSMutableString*out=[NSMutableString string];NSArray*lines=storeArray(chart[@"judgeLineList"]);NSMutableArray*order=[NSMutableArray new],*ranks=[NSMutableArray arrayWithCapacity:lines.count];for(NSUInteger i=0;i<lines.count;i++)[order addObject:@(i)];[order sortUsingComparator:^NSComparisonResult(NSNumber*a,NSNumber*b){NSDictionary*la=lines[a.unsignedIntegerValue],*lb=lines[b.unsignedIntegerValue],*da=la[@"pmDecor"],*db=lb[@"pmDecor"];NSInteger za=[da[@"zOrder"]integerValue],zb=[db[@"zOrder"]integerValue];return za<zb?NSOrderedAscending:za>zb?NSOrderedDescending:(a.unsignedIntegerValue<b.unsignedIntegerValue?NSOrderedAscending:NSOrderedDescending);}];for(NSUInteger i=0;i<lines.count;i++) [ranks addObject:@0];for(NSUInteger i=0;i<order.count;i++)ranks[[order[i]unsignedIntegerValue]]=@(i);for(NSUInteger li=0;li<lines.count;li++){NSDictionary*l=lines[li],*decor=[l[@"pmDecor"]isKindOfClass:NSDictionary.class]?l[@"pmDecor"]:nil;int cover=decor[@"isCover"]?[decor[@"isCover"]intValue]:1;[out appendFormat:@"P %lu %d %d\n",(unsigned long)li,[ranks[li]intValue],cover];appendDecorExtras(out,decor,li);NSString*attach=decor[@"attachUI"];NSArray*uiNames=@[@"pause",@"combonumber",@"combo",@"score",@"bar",@"name",@"level"];NSUInteger uiCode=[uiNames indexOfObjectPassingTest:^BOOL(id obj,NSUInteger idx,BOOL*stop){return [obj caseInsensitiveCompare:attach]==NSOrderedSame;}];if(attach.length&&uiCode!=NSNotFound)[out appendFormat:@"U %lu %lu\n",(unsigned long)li,(unsigned long)uiCode+1];NSString*texture=decor[@"Texture"];if([texture isKindOfClass:NSString.class]&&texture.length&&![texture isEqualToString:@"line.png"]){NSArray*anchor=storeArray(decor[@"anchor"]);[out appendFormat:@"X %lu %@ %.17g %.17g\n",(unsigned long)li,hexUTF8(texture),anchor.count>0?[anchor[0]doubleValue]:.5,anchor.count>1?[anchor[1]doubleValue]:.5];}for(NSDictionary*sp in storeArray(l[@"speedEvents"]))[out appendFormat:@"S %lu %.17g %.17g %.17g %.17g\n",(unsigned long)li,[sp[@"startTime"]doubleValue]/64.,[sp[@"endTime"]doubleValue]/64.,[sp[@"value"]doubleValue],[sp[@"floorPosition"]doubleValue]];for(NSDictionary*ev in storeArray(l[@"judgeLineDisappearEvents"]))[out appendFormat:@"L %lu 5 %.17g %.17g %.17g %.17g\n",(unsigned long)li,[ev[@"startTime"]doubleValue]/64.,[ev[@"endTime"]doubleValue]/64.,[ev[@"start"]doubleValue],[ev[@"end"]doubleValue]];for(int side=0;side<2;side++){NSArray*notes=storeArray(l[side?@"notesBelow":@"notesAbove"]);for(NSUInteger i=0;i<notes.count;i++){NSDictionary*n=notes[i];if(!n[@"pmSize"]&&!n[@"pmFake"]&&!n[@"pmAlpha"]&&!n[@"pmRawSpeed"])continue;[out appendFormat:@"%lu %d %lu %.17g %d %.17g %.17g",(unsigned long)li,side,(unsigned long)i,n[@"pmSize"]?[n[@"pmSize"]doubleValue]:1,[n[@"pmFake"]boolValue],n[@"pmAlpha"]?[n[@"pmAlpha"]doubleValue]:1,n[@"pmVisible"]?[n[@"pmVisible"]doubleValue]:999999.];if(n[@"pmRawSpeed"])[out appendFormat:@" %.17g 0 %.17g %.17g %.17g %.17g\n",[n[@"pmRawSpeed"]doubleValue],[n[@"pmEndFloor"]doubleValue],[n[@"floorPosition"]doubleValue],[n[@"pmTime"]doubleValue],[n[@"pmDuration"]doubleValue]];else[out appendString:@"\n"];}}}return writeText(out,[folder stringByAppendingPathComponent:@"extras.tsv"],e);}
BOOL safeExtensionRelativePath(NSString *raw, BOOL shader, NSString **relative) {
 if(![raw isKindOfClass:NSString.class]||!raw.length)return NO;
 NSString *value=[raw stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
 if(shader){if(![value hasPrefix:@"/"])return NO;value=[value substringFromIndex:1];}
 else if(value.isAbsolutePath||[value hasPrefix:@"/"])return NO;
 if([value containsString:@":"])return NO;
 NSMutableArray *parts=[NSMutableArray new];
 for(NSString *component in [value componentsSeparatedByString:@"/"]){
  if(!component.length||[component isEqualToString:@".."]||[component isEqualToString:@"."])return NO;
  [parts addObject:component];
 }
 if(!parts.count)return NO;
 if(relative)*relative=[parts componentsJoinedByString:@"/"];
 return YES;
}
BOOL copyExtensionResource(NSString *sourceRoot,NSString *extensions,NSString *relative,NSError **error){
 NSFileManager *manager=NSFileManager.defaultManager;
 NSString *source=[[sourceRoot stringByAppendingPathComponent:relative]stringByStandardizingPath];
 NSString *destination=[[extensions stringByAppendingPathComponent:relative]stringByStandardizingPath];
 NSURL *rootURL=[[NSURL fileURLWithPath:sourceRoot isDirectory:YES] URLByResolvingSymlinksInPath];
 NSURL *sourceURL=[[NSURL fileURLWithPath:source] URLByResolvingSymlinksInPath];
 NSURL *destRootURL=[[NSURL fileURLWithPath:extensions isDirectory:YES] URLByResolvingSymlinksInPath];
 if(![source hasPrefix:[sourceRoot stringByAppendingString:@"/"]]||
    ![destination hasPrefix:[extensions stringByAppendingString:@"/"]]||
    ![sourceURL.path hasPrefix:[rootURL.path stringByAppendingString:@"/"]]){
  if(error)*error=err(@"RPE extension resource path escapes its package");return NO;
 }
 BOOL directory=NO;
 if(![manager fileExistsAtPath:source isDirectory:&directory]||directory){if(error)*error=err([NSString stringWithFormat:@"RPE extension resource missing: %@",relative]);return NO;}
 if([sourceURL.path isEqualToString:destination])return YES;
 if(![manager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error])return NO;
 NSURL *resolvedDestination=[[NSURL fileURLWithPath:destination] URLByResolvingSymlinksInPath];
 if(![resolvedDestination.path hasPrefix:[destRootURL.path stringByAppendingString:@"/"]]){if(error)*error=err(@"RPE extension destination escapes its package");return NO;}
 if([manager fileExistsAtPath:destination]){
  if([digest(source) isEqualToString:digest(destination)])return YES;
  if(error)*error=err([NSString stringWithFormat:@"Conflicting RPE extension resource: %@",relative]);return NO;
 }
 NSData *data=[NSData dataWithContentsOfURL:sourceURL options:NSDataReadingMappedIfSafe error:error];
 return data&&[data writeToFile:destination options:NSDataWritingAtomic error:error];
}
BOOL preserveExtraResources(NSString *folder,NSError **error){
 NSFileManager *manager=NSFileManager.defaultManager;
 NSString *extensions=[folder stringByAppendingPathComponent:@"extensions"];
 NSString *canonicalExtra=[extensions stringByAppendingPathComponent:@"extra.json"];
 NSMutableArray *matches=[NSMutableArray new];
 NSDirectoryEnumerator *enumerator=[manager enumeratorAtPath:folder];
 for(NSString *relative in enumerator){
  if([relative.lastPathComponent caseInsensitiveCompare:@"extra.json"]!=NSOrderedSame)continue;
  NSString *path=[folder stringByAppendingPathComponent:relative];
  BOOL directory=NO;if(![manager fileExistsAtPath:path isDirectory:&directory]||directory)continue;
  [matches addObject:path];
 }
 if(!matches.count)return YES;
 NSString *sourceExtra=nil;
 if([matches containsObject:canonicalExtra]){
  for(NSString *candidate in matches)if(![candidate isEqualToString:canonicalExtra]){sourceExtra=candidate;break;}
  if(!sourceExtra)sourceExtra=canonicalExtra;
 }else sourceExtra=matches.firstObject;
 NSData *jsonData=[NSData dataWithContentsOfFile:sourceExtra];
 NSError *jsonError=nil;
 id raw=jsonData?[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&jsonError]:nil;
 if(![raw isKindOfClass:NSDictionary.class]){if(error)*error=err(jsonError.localizedDescription?:@"RPE extra.json is invalid");return NO;}
 for(NSString *candidate in matches){
  if([candidate isEqualToString:sourceExtra])continue;
  if(![[NSData dataWithContentsOfFile:candidate] isEqualToData:jsonData]){if(error)*error=err(@"RPE package contains conflicting extra.json files");return NO;}
 }
 if(![sourceExtra isEqualToString:canonicalExtra]){
  if(![manager createDirectoryAtPath:extensions withIntermediateDirectories:YES attributes:nil error:error]||
     ![jsonData writeToFile:canonicalExtra options:NSDataWritingAtomic error:error])return NO;
 }
 NSString *sourceRoot=sourceExtra.stringByDeletingLastPathComponent;
 NSDictionary *extra=raw;
 id effects=extra[@"effects"];
 if(effects&&![effects isKindOfClass:NSArray.class]){if(error)*error=err(@"RPE effects must be an array");return NO;}
 for(id effect in effects?:@[]){
  if(![effect isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid RPE shader effect entry");return NO;}
  id shader=[effect objectForKey:@"shader"];
  if(![shader isKindOfClass:NSString.class]||![shader hasPrefix:@"/"])continue;
  NSString *relative=nil;
  if(!safeExtensionRelativePath(shader,YES,&relative)){if(error)*error=err(@"Unsafe RPE shader resource path");return NO;}
  if([relative caseInsensitiveCompare:@"extra.json"]==NSOrderedSame){if(error)*error=err(@"RPE shader resource conflicts with extra.json");return NO;}
  if(!copyExtensionResource(sourceRoot,extensions,relative,error))return NO;
 }
 id videos=extra[@"videos"];
 if(videos&&![videos isKindOfClass:NSArray.class]){if(error)*error=err(@"RPE videos must be an array");return NO;}
 for(id video in videos?:@[]){
  if(![video isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid RPE video entry");return NO;}
  NSString *relative=nil;
  if(!safeExtensionRelativePath([video objectForKey:@"path"],NO,&relative)){if(error)*error=err(@"Unsafe RPE video resource path");return NO;}
  if([relative caseInsensitiveCompare:@"extra.json"]==NSOrderedSame){if(error)*error=err(@"RPE video resource conflicts with extra.json");return NO;}
  if(!copyExtensionResource(sourceRoot,extensions,relative,error))return NO;
 }
 for(NSString *candidate in matches)if(![candidate isEqualToString:canonicalExtra]){
  if(![manager removeItemAtPath:candidate error:error])return NO;
 }
 return YES;
}

BOOL prepareAndroidSongFolder(NSString*folder,NSDictionary*chart,NSString*source,NSError**e,bool exporting=false){
 if(!writeJSONCompact(chart,[folder stringByAppendingPathComponent:@"chart.json"],e)||(!exporting&&!writeJSONCompact(PMNativeChart(chart),[folder stringByAppendingPathComponent:@"chart-native.json"],e)))return NO;
 if(!writeConversionMetadata(chart,folder,e)||!writeExtras(chart,folder,e)||!writeText(androidFormat(chart),[folder stringByAppendingPathComponent:@"format.txt"],e)||!writeSourceAudio(source,folder,e))return NO;
 if(!preserveExtraResources(folder,e))return NO;
 NSString*extra=[[folder stringByAppendingPathComponent:@"extensions"]stringByAppendingPathComponent:@"extra.json"];
 return PMConvertExtraJSON(extra,[folder stringByAppendingPathComponent:@"effects.tsv"],e);
}
BOOL copyTree(NSString*from,NSString*to,NSError**e){NSFileManager*f=NSFileManager.defaultManager;if(![f fileExistsAtPath:from]){if(e)*e=err(@"Chart asset folder is missing");return NO;}if(![f createDirectoryAtPath:to withIntermediateDirectories:YES attributes:nil error:e])return NO;for(NSString*rel in [f subpathsOfDirectoryAtPath:from error:nil]){NSString*a=[from stringByAppendingPathComponent:rel],*b=[to stringByAppendingPathComponent:rel];BOOL dir=NO;[f fileExistsAtPath:a isDirectory:&dir];if(dir){if(![f createDirectoryAtPath:b withIntermediateDirectories:YES attributes:nil error:e])return NO;}else if(![f copyItemAtPath:a toPath:b error:e])return NO;}return YES;}
// Every exported song must be self-describing even when several source assets survive.
BOOL writeExportInfo(NSString*folder,NSDictionary*song,NSString*source,NSError**error){
 NSFileManager*f=NSFileManager.defaultManager;
 NSString*music=nil,*prefix=[folder stringByAppendingString:@"/"];
 NSData*data=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"source-audio.json"]];
 id audioMeta=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 NSString*audioName=[audioMeta isKindOfClass:NSDictionary.class]?audioMeta[@"file"]:nil;
 if([audioName isKindOfClass:NSString.class]&&[audioName isEqualToString:audioName.lastPathComponent]&&[f fileExistsAtPath:[folder stringByAppendingPathComponent:audioName]])music=audioName;
 if(!music&&[source hasPrefix:prefix]&&[f fileExistsAtPath:source])music=[source substringFromIndex:prefix.length];
 if(!music){if(error)*error=err(@"Export audio is missing; cannot create import metadata");return NO;}
 // Internal playback audio may be the only surviving source. Give it an export name
 // before stripIOSArtifacts removes music.m4a/music.caf.
 if([@[@"music.m4a",@"music.caf"]containsObject:music]){
  NSString*name=[@"audio.export." stringByAppendingString:music.pathExtension],*dest=[folder stringByAppendingPathComponent:name];
  if([f fileExistsAtPath:dest]&&![f removeItemAtPath:dest error:error])return NO;
  if(![f copyItemAtPath:[folder stringByAppendingPathComponent:music] toPath:dest error:error])return NO;music=name;
 }
 NSString*picture=[f fileExistsAtPath:[folder stringByAppendingPathComponent:@"image.png"]]?@"image.png":@"";
 NSString*level=[NSString stringWithFormat:@"%@ Lv.%@",song[@"level"]?:@"IN",PMDifficultyText(song)];
 NSArray*values=@[@"chart.json",music,picture,song[@"title"]?:@"",song[@"composer"]?:@"",song[@"charter"]?:@"",song[@"illustrator"]?:@"",level];
 NSMutableArray*cells=[NSMutableArray new];for(id value in values){NSString*textValue=[value isKindOfClass:NSString.class]?value:[value description];[cells addObject:[NSString stringWithFormat:@"\"%@\"",[textValue stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]]];}
 NSString*csvText=[NSString stringWithFormat:@"Chart,Song,Picture,Name,Composer,Charter,Illustrator,Level\n%@\n",[cells componentsJoinedByString:@","]];
 return writeText(csvText,[folder stringByAppendingPathComponent:@"info.csv"],error);
}
#include "PMImportCompaction.inc"
void stripIOSArtifacts(NSString*folder){NSFileManager*f=NSFileManager.defaultManager;for(NSString*name in @[@"music.m4a",@"music.caf",@"chart-native.json",@"info.json",@"info.yml",@"info.yaml",@"info.txt"])[f removeItemAtPath:[folder stringByAppendingPathComponent:name] error:nil];for(NSString*rel in [f subpathsOfDirectoryAtPath:folder error:nil])if([rel.lastPathComponent.lowercaseString hasPrefix:@"temp."])[f removeItemAtPath:[folder stringByAppendingPathComponent:rel] error:nil];}

NSString*mapString(NSDictionary*map,NSString*value){if(![value isKindOfClass:NSString.class])return nil;NSString*out=map[value];return [out isKindOfClass:NSString.class]&&out.length?out:value;}
BOOL manifestSafePath(NSString*value){
 if(![value isKindOfClass:NSString.class]||!value.length||value.isAbsolutePath||[value containsString:@"\\"]||[value containsString:@":"])return NO;
 for(NSString*c in [value componentsSeparatedByString:@"/"])if(!c.length||[c isEqualToString:@"."]||[c isEqualToString:@".."])return NO;
 return YES;
}
BOOL manifestSafeReference(NSString*value){if(![value isKindOfClass:NSString.class]||!value.length)return NO;return ![value containsString:@"/"]&&! [value containsString:@"\\"]&&! [value containsString:@".."]&&! [value containsString:@":"];}
void inventoryFail(NSError **error,NSString *message){if(error)*error=err(message);}
BOOL validateManifestInventory(id rawInventory,NSString*root,NSString*stage,NSArray*files,NSError**error){
 if(![rawInventory isKindOfClass:NSArray.class]&&![rawInventory isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Chapter package has no file inventory");return NO;}
 NSMutableSet*expected=[NSMutableSet new];NSFileManager*f=NSFileManager.defaultManager;
 for(id raw in rawInventory){NSString*name=nil;NSNumber*size=nil;NSString*sha=nil;
  if([rawInventory isKindOfClass:NSArray.class]){if(![raw isKindOfClass:NSDictionary.class]){inventoryFail(error,@"Invalid inventory entry");return NO;}name=raw[@"path"];size=raw[@"size"];sha=raw[@"sha256"];}else{name=raw;NSDictionary*entry=rawInventory[name];if(![entry isKindOfClass:NSDictionary.class]){inventoryFail(error,@"Invalid inventory entry");return NO;}sha=entry[@"sha256"];}
  if(!manifestSafePath(name)||[name isEqualToString:@"chapter.json"]||[expected containsObject:name]||![sha isKindOfClass:NSString.class]||sha.length!=64){inventoryFail(error,@"Invalid or duplicate inventory path");return NO;}
  NSString*path=[[root stringByAppendingPathComponent:name]stringByStandardizingPath];NSDictionary*attrs=[f attributesOfItemAtPath:path error:nil];NSString*actualDigest=digest(path);
  if(![path hasPrefix:[stage stringByAppendingString:@"/"]]||!attrs||!actualDigest.length||([size isKindOfClass:NSNumber.class]&&[attrs[NSFileSize] unsignedLongLongValue]!=size.unsignedLongValue)||[actualDigest caseInsensitiveCompare:sha]!=NSOrderedSame){inventoryFail(error,@"Chapter package resource validation failed");return NO;}
  [expected addObject:name];
 }
 NSMutableSet*actual=[NSMutableSet new];NSString*prefix=[root stringByAppendingString:@"/"];for(NSString*path in files){if(![path hasPrefix:prefix])continue;NSString*name=[path substringFromIndex:prefix.length];if([name isEqualToString:@"chapter.json"])continue;if(!manifestSafePath(name)||[actual containsObject:name]){inventoryFail(error,@"Chapter package contains an unexpected or duplicate file");return NO;}[actual addObject:name];}
 if(![actual isEqualToSet:expected]){inventoryFail(error,@"Chapter package contains files outside its manifest");return NO;}return YES;
}
BOOL validateChapterImages(NSString*folder,NSError**error){
 NSFileManager*f=NSFileManager.defaultManager;
 for(NSString*name in @[@"image.png",@"image-before.png",@"image-after.png",@"image-special.png"]){NSString*path=[folder stringByAppendingPathComponent:name];if(![f fileExistsAtPath:path]){if([name isEqualToString:@"image.png"]){if(error)*error=err(@"Chapter package is missing its default cover");return NO;}continue;}
  CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);NSDictionary*p=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;BOOL valid=[p[(NSString*)kCGImagePropertyPixelWidth] doubleValue]>0&&[p[(NSString*)kCGImagePropertyPixelHeight] doubleValue]>0;if(source)CFRelease(source);if(!valid){if(error)*error=err(@"Invalid chapter cover image");return NO;}
 }return YES;
}
BOOL validateUnlockMedia(NSDictionary*entity,NSString*folder,NSError**error){
 NSString*message=PMUnlockValidationError(entity[@"unlock"]);if(message){if(error)*error=err(message);return NO;}
 NSString*name=entity[@"unlock"][@"animation"];if(!name.length)return YES;
 NSString*path=[folder stringByAppendingPathComponent:name];NSDictionary*attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
 if(!attributes||![attributes[NSFileType] isEqualToString:NSFileTypeRegular]||![attributes[NSFileSize] unsignedLongLongValue]){if(error)*error=err(@"Unlock animation resource is missing");return NO;}
 if([name.pathExtension isEqualToString:@"gif"]){
  if([attributes[NSFileSize] unsignedLongLongValue]>32ull*1024*1024){if(error)*error=err(@"Unlock GIF exceeds 32 MB");return NO;}
  CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);BOOL valid=source&&CGImageSourceGetCount(source)>0;double duration=0;
  for(size_t i=0;valid&&i<CGImageSourceGetCount(source);++i){NSDictionary*p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,i,NULL));double w=[p[(NSString*)kCGImagePropertyPixelWidth] doubleValue],h=[p[(NSString*)kCGImagePropertyPixelHeight] doubleValue];NSDictionary*g=p[(NSString*)kCGImagePropertyGIFDictionary];double delay=[(g[(NSString*)kCGImagePropertyGIFUnclampedDelayTime]?:g[(NSString*)kCGImagePropertyGIFDelayTime]) doubleValue];if(!std::isfinite(delay)||delay<.02)delay=.1;duration+=delay;valid=w>0&&h>0&&w<=4096&&h<=4096&&duration<=600;}
  if(source)CFRelease(source);if(!valid){if(error)*error=err(@"Invalid unlock GIF dimensions or duration");return NO;}
 }
 else{AVURLAsset*asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];double seconds=CMTimeGetSeconds(asset.duration);NSArray*tracks=[asset tracksWithMediaType:AVMediaTypeVideo];AVAssetTrack*track=tracks.firstObject;CGSize size=track.naturalSize;if(!track||!std::isfinite(seconds)||seconds<=0||seconds>600||size.width<=0||size.height<=0||size.width>4096||size.height>4096){if(error)*error=err(@"Invalid unlock video dimensions or duration");return NO;}}
 return YES;
}
BOOL validateUnlockReferences(NSDictionary*entity,NSDictionary*songMap,NSDictionary*chapterMap,NSSet*officialSongs,NSSet*officialChapters,NSError**error){
 NSString*validation=PMUnlockValidationError(entity[@"unlock"]);if(validation){if(error)*error=err(validation);return NO;}
 NSDictionary*rule=entity[@"unlock"];
 for(NSDictionary*c in rule[@"conditions"]){
  NSString*type=c[@"type"],*ref=c[@"ref"];if([type isEqualToString:@"rks"])continue;
  BOOL chapter=[type isEqualToString:@"chapter"];
  if(!(chapter?chapterMap[ref]:songMap[ref])&&![(chapter?officialChapters:officialSongs) containsObject:ref]){if(error)*error=err([NSString stringWithFormat:@"Unlock condition %@ in %@ references missing %@: %@. Import the dependency chapter/song first or export it with the package.",type,entity[@"id"]?:@"?",chapter?@"chapter":@"song",ref]);return NO;}
 }
 NSDictionary*chain=rule[@"chain"];NSString*next=chain[@"song"];
 if([chain[@"enabled"] boolValue]&&!songMap[next]&&![officialSongs containsObject:next]){if(error)*error=err(@"Unlock chain references a missing song");return NO;}
 id cover=entity[@"coverSwitch"];if(cover&&![cover isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid cover switch");return NO;}
 NSString*mode=cover[@"mode"]?:@"none";if(![@[@"none",@"unlock"] containsObject:mode]){NSMutableDictionary*c=[cover mutableCopy];[c removeObjectForKey:@"mode"];c[@"type"]=mode;NSString*invalid=PMUnlockValidationError(@{@"enabled":@YES,@"conditions":@[c]});if(invalid||[mode isEqualToString:@"chapter"]){if(error)*error=err(invalid?:@"Unsupported cover condition");return NO;}}
 id ref=cover[@"ref"];if(ref&&(![ref isKindOfClass:NSString.class]||([ref length]&&!songMap[ref]&&![officialSongs containsObject:ref]))){if(error)*error=err(@"Cover switch references a missing song");return NO;}
 return YES;
}
NSMutableDictionary*remapUnlockEntity(NSDictionary*source,NSDictionary*songMap,NSDictionary*chapterMap,NSDictionary*ruleMap){
 NSString*validation=PMUnlockValidationError(source[@"unlock"]);if(validation)@throw [NSException exceptionWithName:@"InvalidUnlockRule" reason:validation userInfo:nil];NSMutableDictionary*out=clone(source);if(!out)return nil;[out removeObjectForKey:@"unlockProgress"];NSMutableDictionary*rule=[out[@"unlock"] isKindOfClass:NSDictionary.class]?[out[@"unlock"] mutableCopy]:nil;if(rule){[rule removeObjectForKey:@"unlocked"];[rule removeObjectForKey:@"seen"];NSMutableArray*conditions=[rule[@"conditions"] isKindOfClass:NSArray.class]?[rule[@"conditions"] mutableCopy]:nil;for(NSMutableDictionary*c in conditions){NSString*type=c[@"type"],*ref=c[@"ref"];if([ref isKindOfClass:NSString.class]&&![type isEqualToString:@"rks"])c[@"ref"]=mapString([type isEqualToString:@"chapter"]?chapterMap:ruleMap,ref);}rule[@"conditions"]=conditions?:@[];NSMutableDictionary*chain=[rule[@"chain"] isKindOfClass:NSDictionary.class]?[rule[@"chain"] mutableCopy]:nil;if(chain&&[chain[@"song"] isKindOfClass:NSString.class])chain[@"song"]=mapString(ruleMap,chain[@"song"]);if(chain)rule[@"chain"]=chain;out[@"unlock"]=rule;}NSMutableDictionary*cover=[out[@"coverSwitch"] isKindOfClass:NSDictionary.class]?[out[@"coverSwitch"] mutableCopy]:nil;if(cover&&[cover[@"ref"] isKindOfClass:NSString.class])cover[@"ref"]=mapString(ruleMap,cover[@"ref"]);if(cover)out[@"coverSwitch"]=cover;return out;
}
NSArray*remapSongOrder(NSArray*source,NSDictionary*songMap,NSSet*official,NSError**error){NSMutableArray*out=[NSMutableArray new];NSMutableSet*seen=[NSMutableSet new];for(NSString*old in source){NSString*value=songMap[old]?:old;if(![songMap[old] isKindOfClass:NSString.class]&&! [official containsObject:old]){if(error)*error=err(@"Chapter dependency references an unknown song");return nil;}if([seen containsObject:value]){if(error)*error=err(@"Chapter song order contains duplicates");return nil;}[seen addObject:value];[out addObject:value];}return out;}
@interface PMContentStore ()
@property(nonatomic,copy,readwrite) NSString*root;
@property(nonatomic,readwrite) NSUInteger revision;
@property(nonatomic,strong) NSMutableDictionary*db;
@end
@implementation PMContentStore
+ (instancetype)shared{static PMContentStore*s;static dispatch_once_t once;dispatch_once(&once,^{s=[PMContentStore new];});return s;}
- (instancetype)init{if((self=[super init])){self.root=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"PhiMod"];NSFileManager*f=NSFileManager.defaultManager;for(NSString*name in @[@"assets",@"imports",@"exports",@"trash"])[f createDirectoryAtPath:[self.root stringByAppendingPathComponent:name] withIntermediateDirectories:YES attributes:nil error:nil];NSData*d=[NSData dataWithContentsOfFile:[self.root stringByAppendingPathComponent:@"library.json"]];self.db=d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;if(!self.db){NSData*backup=[NSData dataWithContentsOfFile:[self.root stringByAppendingPathComponent:@"library.backup.json"]];self.db=backup?[NSJSONSerialization JSONObjectWithData:backup options:NSJSONReadingMutableContainers error:nil]:nil;}if(!self.db)self.db=[@{@"songs":[NSMutableArray new],@"chapters":[@[[ @{@"id":@"pm_local",@"name":@"自制谱收藏",@"subtitle":@"LOCAL CHARTS",@"songs":@[]} mutableCopy]] mutableCopy],@"overrides":[NSMutableDictionary new],@"hiddenChapters":[NSMutableArray new],@"chartSelections":[NSMutableDictionary new]} mutableCopy];// Previous process exports are staging copies, never the user's saved output.
 for(NSString*name in [f contentsOfDirectoryAtPath:[self.root stringByAppendingPathComponent:@"exports"] error:nil])if([name.pathExtension.lowercaseString isEqualToString:@"zip"])[self cleanupExports:@[[NSURL fileURLWithPath:[[self.root stringByAppendingPathComponent:@"exports"]stringByAppendingPathComponent:name]]]];
 recoverChapterImports(self.root,self.db);self.revision=1;}return self;}
- (NSDictionary*)snapshot{@synchronized(self){return clone(self.db);}}
- (BOOL)saveUnlockRule:(NSDictionary*)rule animationURL:(NSURL*)url identifier:(NSString*)identifier error:(NSError**)error{
 @synchronized(self){
  NSMutableDictionary*db=clone([self snapshot]),*subject=nil;
  for(NSString*key in @[@"songs",@"chapters"])for(NSMutableDictionary*e in db[key])if([e[@"id"]isEqual:identifier])subject=e;
  if(!subject){if(error)*error=err(@"Entity was deleted; changes not saved");return NO;}
  NSMutableDictionary*updated=[rule mutableCopy];NSString*invalid=PMUnlockValidationError(updated);if(invalid){if(error)*error=err(invalid);return NO;}
  NSString*copied=nil;NSFileManager*f=NSFileManager.defaultManager;
  if(url){
   NSString*ext=url.pathExtension.lowercaseString;if(![@[@"mp4",@"gif"]containsObject:ext]){if(error)*error=err(@"Select MP4 or GIF");return NO;}
   NSString*folder=[self asset:identifier];if(![f createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error])return NO;
   NSString*name=[NSString stringWithFormat:@"unlock-%@.%@",NSUUID.UUID.UUIDString,ext];copied=[folder stringByAppendingPathComponent:name];
   if(![f copyItemAtURL:url toURL:[NSURL fileURLWithPath:copied] error:error])return NO;updated[@"animation"]=name;
  }
  subject[@"unlock"]=updated;[subject removeObjectForKey:@"unlockProgress"];
  if(!validateUnlockMedia(subject,[self asset:identifier],error)||![self commit:db error:error]){if(copied)[f removeItemAtPath:copied error:nil];return NO;}
  return YES;
 }
}
- (NSString*)coverFolder:(NSString*)identifier{
 if(![identifier isKindOfClass:NSString.class]||!identifier.length)return nil;
 if(safeID(identifier))return [self asset:identifier];
 NSDictionary*official=pmcontent::cachedOfficialSnapshot();static NSDictionary*cachedCatalog=nil;static NSSet*knownIDs=nil;
 @synchronized(self){if(cachedCatalog!=official){NSMutableSet*ids=[NSMutableSet setWithArray:PMOfficialSongMap(official).allKeys];for(NSDictionary*c in official[@"chapters"])if(c[@"chapterCode"])[ids addObject:c[@"chapterCode"]];knownIDs=ids;cachedCatalog=official;}if(![knownIDs containsObject:identifier])return nil;}NSData*data=[identifier dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);NSMutableString*key=[@"pm_official_" mutableCopy];for(unsigned char b:hash)[key appendFormat:@"%02x",b];return [self asset:key];
}
- (BOOL)assignSongs:(NSArray<NSString*>*)ids toChapter:(NSString*)chapter move:(BOOL)move error:(NSError**)error{
 @synchronized(self){NSMutableDictionary*db=clone([self snapshot]);if(!PMAssignChapterSongs(db,pmcontent::cachedOfficialSnapshot(),ids,chapter,move,error))return NO;return [self commit:db error:error];}
}
- (NSString*)asset:(NSString*)identifier{return safeID(identifier)?[[self.root stringByAppendingPathComponent:@"assets"]stringByAppendingPathComponent:identifier]:nil;}
- (BOOL)commit:(NSDictionary*)value error:(NSError**)error{@synchronized(self){if(![value[@"songs"] isKindOfClass:NSArray.class]||![value[@"chapters"] isKindOfClass:NSArray.class]){if(error)*error=err(@"曲库结构无效");return NO;}NSMutableSet*ids=[NSMutableSet new];for(NSDictionary*s in value[@"songs"]){NSString*i=s[@"id"];if(!safeID(i)||[ids containsObject:i]){if(error)*error=err(@"谱面 ID 重复或不合法");return NO;}[ids addObject:i];}NSMutableSet*chapterIDs=[NSMutableSet new];for(NSDictionary*c in value[@"chapters"]){if(!safeID(c[@"id"])||[chapterIDs containsObject:c[@"id"]]||![c[@"name"] length]){if(error)*error=err(@"章节 ID 或名称无效");return NO;}[chapterIDs addObject:c[@"id"]];}NSString*p=[self.root stringByAppendingPathComponent:@"library.json"];if([NSFileManager.defaultManager fileExistsAtPath:p]&&![[NSData dataWithContentsOfFile:p] writeToFile:[self.root stringByAppendingPathComponent:@"library.backup.json"] options:NSDataWritingAtomic error:error])return NO;if(!writeJSON(value,p,error))return NO;self.db=clone(value);self.revision++;return YES;}}
- (BOOL)replaceImage:(NSURL*)url identifier:(NSString*)identifier error:(NSError**)error{NSData*data=[NSData dataWithContentsOfURL:url];if(!data){if(error)*error=err(@"Unable to read image data.");return NO;}return [self replaceImageData:data identifier:identifier error:error];}
- (BOOL)replaceImageData:(NSData*)data identifier:(NSString*)identifier error:(NSError**)error{NSString*folder=[self coverFolder:identifier];if(!folder){if(error)*error=err(@"Invalid asset ID");return NO;}UIImage*image=[UIImage imageWithData:data];if(!image||!image.CGImage){if(error)*error=err(@"Unable to read image");return NO;}CGFloat sourceW=image.size.width*image.scale,sourceH=image.size.height*image.scale;if(sourceW<=0||sourceH<=0){if(error)*error=err(@"Unable to read image");return NO;}CGFloat factor=MIN(1.0,2048.0/MAX(sourceW,sourceH));CGSize size=CGSizeMake(MAX(1,round(sourceW*factor)),MAX(1,round(sourceH*factor)));UIGraphicsImageRendererFormat*format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;UIGraphicsImageRenderer*r=[[UIGraphicsImageRenderer alloc]initWithSize:size format:format];NSData*png=UIImagePNGRepresentation([r imageWithActions:^(UIGraphicsImageRendererContext*c){[image drawInRect:CGRectMake(0,0,size.width,size.height)];}]);if(!png){if(error)*error=err(@"Unable to read image");return NO;}[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error];BOOL ok=[png writeToFile:[folder stringByAppendingPathComponent:@"image.png"] options:NSDataWritingAtomic error:error];if(ok)@synchronized(self){self.revision++;}return ok;}
- (BOOL)importURL:(NSURL*)url chapter:(NSString*)chapter error:(NSError**)error{
 NSFileManager*f=NSFileManager.defaultManager;NSString*stage=[[self.root stringByAppendingPathComponent:@"imports"]stringByAppendingPathComponent:NSUUID.UUID.UUIDString];if(![f createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:error])return NO;BOOL access=[url startAccessingSecurityScopedResource];BOOL ok=NO;NSString*journalPath=nil;NSMutableArray*moved=[NSMutableArray new];
 @try{NSFileCoordinator*coordinator=[[NSFileCoordinator alloc]initWithFilePresenter:nil];__block NSArray*files=nil;__block NSError*readError=nil;[coordinator coordinateReadingItemAtURL:url options:0 error:&readError byAccessor:^(NSURL*readURL){files=PMExtractArchive(readURL.path,stage,&readError);}];if(!files){if(error)*error=readError;return NO;}
 NSString*manifestPath=nil;for(NSString*p in files)if([p.lastPathComponent.lowercaseString isEqualToString:@"chapter.json"]){manifestPath=p;break;}
 if(manifestPath){
  NSDictionary*manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifestPath] options:NSJSONReadingMutableContainers error:error];
  int version=[manifest[@"version"] intValue];
  if(![manifest[@"format"] isEqualToString:@"phigros-phi-chapter"]||version<1||version>3){if(error)*error=err(@"Chapter package format is unsupported");return NO;}
  NSString*root=manifestPath.stringByDeletingLastPathComponent;
   if(!validateManifestInventory(manifest[@"files"],root,stage,files,error))return NO;
  NSMutableDictionary*db=clone([self snapshot]);NSMutableDictionary*songMap=[NSMutableDictionary new],*chapterMap=[NSMutableDictionary new],*groupMap=[NSMutableDictionary new],*ruleMap=[NSMutableDictionary new];
  id rawChapter=manifest[@"chapter"];if(![rawChapter isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Chapter manifest is missing");return NO;}NSDictionary*sourceChapter=rawChapter;NSString*oldMain=sourceChapter[@"id"];if(!manifestSafeReference(oldMain)||![sourceChapter[@"songs"] isKindOfClass:NSArray.class]){if(error)*error=err(@"Chapter ID is invalid");return NO;}NSString*mainID=fresh();chapterMap[oldMain]=mainID;
  id rawDependencies=manifest[@"dependencyChapters"];if(rawDependencies&&![rawDependencies isKindOfClass:NSArray.class]){if(error)*error=err(@"Invalid dependency chapter list");return NO;}NSArray*sourceDependencies=rawDependencies?:@[];if(sourceDependencies.count>128){if(error)*error=err(@"Too many dependency chapters");return NO;}
  for(id rawDependency in sourceDependencies){if(![rawDependency isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid dependency chapter");return NO;}NSDictionary*dep=rawDependency;NSString*old=dep[@"id"];if(!manifestSafeReference(old)||chapterMap[old]||![dep[@"songs"] isKindOfClass:NSArray.class]){if(error)*error=err(@"Dependency chapter ID is invalid");return NO;}chapterMap[old]=fresh();}
  id rawSongs=manifest[@"songs"];if(rawSongs&&![rawSongs isKindOfClass:NSArray.class]){if(error)*error=err(@"Invalid song list");return NO;}NSArray*sourceSongs=rawSongs?:@[];if(sourceSongs.count>2000){if(error)*error=err(@"Too many songs in chapter package");return NO;}
  NSMutableSet*official=[NSMutableSet new];NSMutableArray*officialOrder=[NSMutableArray new];NSDictionary*base=pmcontent::cachedOfficialSnapshot()[@"songBase"];
  NSMutableSet*available=[NSMutableSet new];for(NSString*key in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSDictionary*song in base[key])if(song[@"songsId"])[available addObject:song[@"songsId"]];
  NSArray*validatedOfficial=PMChapterOfficialReferences(manifest[@"officialSongs"],PMOfficialChapterEntries(pmcontent::cachedOfficialSnapshot()),error);if(!validatedOfficial)return NO;[official addObjectsFromArray:validatedOfficial];[officialOrder addObjectsFromArray:validatedOfficial];
  NSMutableSet*importSongIDs=reservedSongIDs(self);
  for(id rawSourceSong in sourceSongs){if(![rawSourceSong isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid song entry");return NO;}NSDictionary*sourceSong=rawSourceSong;NSString*old=sourceSong[@"id"];if(!safeID(old)||songMap[old]){if(error)*error=err(@"Chapter package song ID is invalid");return NO;}songMap[old]=readableSongID(sourceSong[@"title"],sourceSong[@"charter"],sourceSong[@"level"],importSongIDs);NSString*oldGroup=sourceSong[@"groupId"]?:old;if(!manifestSafeReference(oldGroup)){if(error)*error=err(@"Invalid song group");return NO;}if(!groupMap[oldGroup])groupMap[oldGroup]=songMap[old];}
  [ruleMap addEntriesFromDictionary:groupMap];[ruleMap addEntriesFromDictionary:songMap];
  NSMutableSet*officialChapters=[NSMutableSet new];for(NSDictionary*c in pmcontent::cachedOfficialSnapshot()[@"chapters"])if(c[@"chapterCode"])[officialChapters addObject:c[@"chapterCode"]];
  NSMutableArray*entities=[sourceSongs mutableCopy];[entities addObjectsFromArray:sourceDependencies];[entities addObject:sourceChapter];
  // Normalize decoded mutable entities before validation/remapping/media checks.
  for(NSMutableDictionary*entity in entities){id rule=PMNormalizeUnlockRule(entity[@"unlock"]);if(rule)entity[@"unlock"]=rule;else[entity removeObjectForKey:@"unlock"];if(entity[@"coverSwitch"]==NSNull.null)[entity removeObjectForKey:@"coverSwitch"];}
  // Dependencies may already be installed locally. Package mappings win on
  // collision; otherwise keep the installed ID so rules remain meaningful.
  for(NSDictionary*local in db[@"songs"]){NSString*sid=local[@"id"],*gid=local[@"groupId"];if(sid&&!ruleMap[sid])ruleMap[sid]=sid;if(gid&&!ruleMap[gid])ruleMap[gid]=gid;}
  NSMutableDictionary*unlockChapterMap=[chapterMap mutableCopy];
  for(NSDictionary*local in db[@"chapters"]){NSString*cid=local[@"id"];if(cid&&!unlockChapterMap[cid])unlockChapterMap[cid]=cid;}
  for(NSDictionary*entity in entities)if(!validateUnlockReferences(entity,ruleMap,unlockChapterMap,available,officialChapters,error))return NO;
  if(!validateUnlockMedia(sourceChapter,[root stringByAppendingPathComponent:@"chapter"],error)||!validateChapterImages([root stringByAppendingPathComponent:@"chapter"],error))return NO;
  for(NSDictionary*dep in sourceDependencies){NSString*folder=[root stringByAppendingPathComponent:[@"chapters/" stringByAppendingString:dep[@"id"]]];if(!validateUnlockMedia(dep,folder,error)||!validateChapterImages(folder,error))return NO;}
  for(NSDictionary*song in sourceSongs)if(!validateUnlockMedia(song,[root stringByAppendingPathComponent:[@"songs/" stringByAppendingString:song[@"id"]]],error))return NO;
  NSString*journalDirectory=[self.root stringByAppendingPathComponent:@"import-journals"];
  if(![f createDirectoryAtPath:journalDirectory withIntermediateDirectories:YES attributes:nil error:error])return NO;
  journalPath=[journalDirectory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".json"]];
  NSMutableArray*planned=[songMap.allValues mutableCopy];[planned addObjectsFromArray:chapterMap.allValues];
  if(!writeJSON(@{@"version":@1,@"ids":planned},journalPath,error))return NO;
  NSMutableArray*mappedSongs=[NSMutableArray new];
  for(NSDictionary*sourceSong in sourceSongs){NSString*old=sourceSong[@"id"],*identifier=songMap[old],*folder=[[root stringByAppendingPathComponent:@"songs"]stringByAppendingPathComponent:old];if(![f fileExistsAtPath:folder]){if(error)*error=err(@"Chapter package song resources are missing");return NO;}
   NSString*sourceChart=nil;for(NSString*candidate in @[@"source.rpe.json",@"source.pec",@"chart.json"]){NSString*path=[folder stringByAppendingPathComponent:candidate];if([f fileExistsAtPath:path]){sourceChart=path;break;}}if(!sourceChart&&[sourceSong[@"sourceChart"] isKindOfClass:NSString.class]){NSString*path=[folder stringByAppendingPathComponent:sourceSong[@"sourceChart"]];if([f fileExistsAtPath:path])sourceChart=path;}if(!sourceChart){if(error)*error=err(@"Chapter package chart resource is missing");return NO;}
   NSDictionary*chart=PMConvertChart([NSData dataWithContentsOfFile:sourceChart],error);if(!chart)return NO;NSMutableArray*resources=[NSMutableArray new];for(NSString*rel in [f subpathsOfDirectoryAtPath:folder error:nil]){BOOL dir=NO;NSString*path=[folder stringByAppendingPathComponent:rel];[f fileExistsAtPath:path isDirectory:&dir];if(!dir)[resources addObject:path];}NSString*music=locate(resources,sourceSong[@"sourceMusic"],@[@"ogg",@"mp3",@"wav",@"flac",@"m4a",@"caf",@"pcm"],NO,error);NSString*musicDest=[folder stringByAppendingPathComponent:@"music.m4a"];if(!music||(![music isEqualToString:musicDest]&&!audio(music,musicDest,error)))return NO;NSString*sourceOriginal=sourceChart;if([chart[@"pmFormat"] isEqualToString:@"RPE"]){for(NSString*path in resources)if([path.lastPathComponent.lowercaseString hasSuffix:@".rpe.json"]){sourceOriginal=path;break;}}else if([chart[@"pmFormat"] isEqualToString:@"PEC"]){for(NSString*path in resources)if([path.pathExtension.lowercaseString isEqualToString:@"pec"]){sourceOriginal=path;break;}}
   if([chart[@"pmFormat"] isEqualToString:@"RPE"]&&![[NSData dataWithContentsOfFile:sourceOriginal]writeToFile:[folder stringByAppendingPathComponent:@"source.rpe.json"] options:NSDataWritingAtomic error:error])return NO;if([chart[@"pmFormat"] isEqualToString:@"PEC"]&&![[NSData dataWithContentsOfFile:sourceOriginal]writeToFile:[folder stringByAppendingPathComponent:@"source.pec"] options:NSDataWritingAtomic error:error])return NO;if(!prepareAndroidSongFolder(folder,chart,music,error))return NO;
   if(!PMNormalizeCoverFolder(folder,16.0/9.0,error))return NO;
   NSMutableDictionary*referenceInfo=[sourceSong mutableCopy];[referenceInfo removeObjectForKey:@"sourceChart"];[referenceInfo removeObjectForKey:@"sourceMusic"];
   NSDictionary*compact=compactImportedSong(folder,sourceOriginal,music,chart,referenceInfo,error);if(!compact)return NO;
   NSString*destination=[self asset:identifier];if([f fileExistsAtPath:destination]||![f moveItemAtPath:folder toPath:destination error:error])return NO;[moved addObject:destination];NSMutableDictionary*song=remapUnlockEntity(sourceSong,songMap,chapterMap,ruleMap);[song addEntriesFromDictionary:compact];song[@"id"]=identifier;song[@"groupPinned"]=@YES;song[@"groupSeparate"]=@NO;song[@"groupPending"]=@NO;song[@"groupId"]=groupMap[sourceSong[@"groupId"]?:old];song[@"targetChapter"]=chapterMap[sourceSong[@"targetChapter"]?:oldMain]?:mainID;song[@"beforeSong"]=ruleMap[song[@"beforeSong"]?:@""]?:@"";[mappedSongs addObject:song];}
  NSMutableArray*mappedChapters=[NSMutableArray new];
  for(NSDictionary*sourceDep in sourceDependencies){NSString*old=sourceDep[@"id"],*newID=chapterMap[old];NSMutableDictionary*dep=remapUnlockEntity(sourceDep,songMap,chapterMap,ruleMap);NSArray*order=remapSongOrder(sourceDep[@"songs"],songMap,official,error);if(!order)return NO;dep[@"id"]=newID;dep[@"songs"]=order;dep[@"before"]=mainID;[mappedChapters addObject:dep];NSString*from=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"chapters/%@",old]],*to=[self asset:newID];if([f fileExistsAtPath:from]){if([f fileExistsAtPath:to]||![f copyItemAtPath:from toPath:to error:error])return NO;[moved addObject:to];if(!PMNormalizeCoverFolder(to,1.35625,error))return NO;}}
  NSMutableDictionary*main=remapUnlockEntity(sourceChapter,songMap,chapterMap,ruleMap);NSArray*mainOrder=remapSongOrder(sourceChapter[@"songs"],songMap,official,error);if(!mainOrder)return NO;if(version<3){NSMutableArray*legacy=[mainOrder mutableCopy];for(NSDictionary*legacySong in sourceSongs){NSString*old=legacySong[@"id"];if(![legacy containsObject:songMap[old]])[legacy addObject:songMap[old]];}for(NSString*officialID in officialOrder)if(![legacy containsObject:officialID]){if(error)*error=err(@"Legacy package omits an official song from chapter order");return NO;}mainOrder=legacy;}main[@"id"]=mainID;main[@"songs"]=mainOrder;main[@"before"]=@"";[db[@"chapters"] addObjectsFromArray:mappedChapters];[db[@"chapters"] addObject:main];for(NSDictionary*song in mappedSongs)[db[@"songs"] addObject:song];
  NSString*cover=[root stringByAppendingPathComponent:@"chapter"];if([f fileExistsAtPath:cover]){NSString*to=[self asset:mainID];if([f fileExistsAtPath:to]||![f copyItemAtPath:cover toPath:to error:error])return NO;[moved addObject:to];if(!PMNormalizeCoverFolder(to,1.35625,error))return NO;}
  NSMutableDictionary*selections=clone(db[@"chartSelections"]?:@{});NSDictionary*sourceSelections=manifest[@"selections"];
  if(sourceSelections&&![sourceSelections isKindOfClass:NSDictionary.class]){if(error)*error=err(@"Invalid chart selections");return NO;}
  for(NSString*key in sourceSelections){
   id value=sourceSelections[key];NSRange split=[key rangeOfString:@"@" options:NSBackwardsSearch];
   if(split.location==NSNotFound){if(error)*error=err(@"Invalid selection key");return NO;}
   NSString*oldGroup=[key substringToIndex:split.location],*slot=[key substringFromIndex:split.location+1];
   if(![@[@"0",@"1",@"2",@"3",@"4"] containsObject:slot]||!groupMap[oldGroup]||![value isKindOfClass:NSString.class]||!songMap[value]){if(error)*error=err(@"Unknown selection group, slot or song");return NO;}
   BOOL belongs=NO;for(NSDictionary*song in sourceSongs)if([song[@"id"] isEqualToString:value]&&[(song[@"groupId"]?:song[@"id"]) isEqualToString:oldGroup])belongs=YES;
   if(!belongs){if(error)*error=err(@"Selection song is not in its group");return NO;}
   selections[[NSString stringWithFormat:@"%@@%@",groupMap[oldGroup],slot]]=songMap[value];
  }
  db[@"chartSelections"]=selections;ok=[self commit:db error:error];return ok;
 }
 NSMutableDictionary*meta=[NSMutableDictionary new];for(NSString*p in files){NSString*name=p.lastPathComponent.lowercaseString;if([@[@"info.yml",@"info.yaml",@"info.txt"]containsObject:name]){for(NSString*line in [text(p)componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSRange colon=[line rangeOfString:@":"];if(colon.location==NSNotFound)continue;NSString*k=[[line substringToIndex:colon.location]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;NSString*v=[[line substringFromIndex:colon.location+1]stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \"'"]];meta[k]=v;}}else if([name isEqualToString:@"info.csv"]){NSArray*rows=csv(text(p));if(rows.count>2){if(error)*error=err(@"info.csv contains multiple charts; import each chart separately");return NO;}if(rows.count>1){NSArray*headers=rows[0],*values=rows[1];for(NSUInteger i=0;i<MIN(headers.count,values.count);++i)meta[[headers[i]lowercaseString]]=values[i];}}else if([name isEqualToString:@"info.json"]){id value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:p] options:0 error:nil];if([value isKindOfClass:NSDictionary.class])for(NSString*k in value)meta[k.lowercaseString]=value[k];}}
 NSString*chart=locate(files,meta[@"chart"],@[@"json",@"pec"],NO,error),*music=locate(files,meta[@"song"]?:meta[@"music"],@[@"ogg",@"mp3",@"wav",@"flac",@"m4a",@"caf",@"pcm"],NO,error),*image=locate(files,meta[@"picture"]?:meta[@"illustration"],@[@"png",@"jpg",@"jpeg",@"webp"],YES,error);if(!chart||!music||(error&&*error))return NO;NSDictionary*converted=PMConvertChart([NSData dataWithContentsOfFile:chart],error);if(!converted)return NO;NSString*sourceOriginal=sourceChartFor(files,converted,chart);NSString*identifier=readableSongID(meta[@"name"]?:meta[@"title"]?:chart.lastPathComponent.stringByDeletingPathExtension,meta[@"charter"]?:meta[@"designer"],meta[@"level"],reservedSongIDs(self)),*destination=[self asset:identifier],*importRoot=chart.stringByDeletingLastPathComponent; if(![f createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error])return NO;[moved addObject:destination];NSString*rootPrefix=[importRoot stringByAppendingString:@"/"];for(NSString*p in files){if(![p hasPrefix:rootPrefix]&&![p isEqualToString:importRoot])continue;NSString*relative=[p hasPrefix:rootPrefix]?[p substringFromIndex:rootPrefix.length]:p.lastPathComponent;if(!relative.length)continue;NSString*dest=[destination stringByAppendingPathComponent:relative];BOOL dir=NO;[f fileExistsAtPath:p isDirectory:&dir];if(dir){[f createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];continue;}[f createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];if(![f copyItemAtPath:p toPath:dest error:error])return NO;}
 if([converted[@"pmFormat"]isEqualToString:@"RPE"]&&![[NSData dataWithContentsOfFile:sourceOriginal]writeToFile:[destination stringByAppendingPathComponent:@"source.rpe.json"] options:NSDataWritingAtomic error:error])return NO;if([converted[@"pmFormat"]isEqualToString:@"PEC"]&&[sourceOriginal.pathExtension.lowercaseString isEqualToString:@"pec"]&&![[NSData dataWithContentsOfFile:sourceOriginal]writeToFile:[destination stringByAppendingPathComponent:@"source.pec"] options:NSDataWritingAtomic error:error])return NO;if(!writeJSONCompact(converted,[destination stringByAppendingPathComponent:@"chart.json"],error)||!writeJSONCompact(PMNativeChart(converted),[destination stringByAppendingPathComponent:@"chart-native.json"],error)||!audio(music,[destination stringByAppendingPathComponent:@"music.m4a"],error)||!prepareAndroidSongFolder(destination,converted,music,error))return NO;if(image&&![self replaceImage:[NSURL fileURLWithPath:image] identifier:identifier error:error])return NO;if(!PMNormalizeCoverFolder(destination,16.0/9.0,error))return NO;
 NSMutableDictionary*db=clone([self snapshot]);NSString*target=chapter.length?chapter:@"pm_local";NSMutableDictionary*found=nil;for(NSMutableDictionary*c in db[@"chapters"])if([c[@"id"]isEqualToString:target])found=c;if(!found){if(error)*error=err(@"Target chapter does not exist");return NO;}NSString*level=[meta[@"level"]isKindOfClass:NSString.class]?meta[@"level"]:@"IN";double difficulty=0;NSScanner*scanner=[NSScanner scannerWithString:level];for(NSUInteger i=0;i<level.length;++i)if([[NSCharacterSet decimalDigitCharacterSet]characterIsMember:[level characterAtIndex:i]]){scanner.scanLocation=i;[scanner scanDouble:&difficulty];break;}NSString*trim=PMDifficultyName(level);NSArray*pieces=[trim componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSString*slot=pieces.firstObject.length?pieces.firstObject:@"IN";int stock=PMStockDifficulty(slot);if(stock>=0)slot=slot.uppercaseString;
 NSString*label=@"";NSRange lv=[trim rangeOfString:@"Lv." options:NSCaseInsensitiveSearch];if(lv.location!=NSNotFound)label=[[trim substringFromIndex:NSMaxRange(lv)]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];else if(pieces.count>1)label=[[pieces subarrayWithRange:NSMakeRange(1,pieces.count-1)]componentsJoinedByString:@" "];else if(difficulty>0)label=[@(difficulty)description];difficulty=PMDifficultyNumber(label);
 NSMutableDictionary*song=[@{@"id":identifier,@"groupId":identifier,@"title":meta[@"name"]?:meta[@"title"]?:chart.lastPathComponent.stringByDeletingPathExtension,@"composer":meta[@"composer"]?:meta[@"artist"]?:@"",@"charter":meta[@"charter"]?:meta[@"designer"]?:@"",@"illustrator":meta[@"illustrator"]?:@"",@"level":slot,@"difficulty":@(difficulty),@"difficultyText":label,@"difficultyLabel":slot,@"preview":@0,@"previewEnd":@15,@"offsetMs":@0,@"targetChapter":target,@"sourceFormat":converted[@"pmFormat"]?:@"Phigros v3",@"resourceRoot":@"",@"sourceMusic":music.lastPathComponent,@"sourceChart":sourceOriginal.lastPathComponent}mutableCopy];NSMutableDictionary*referenceInfo=[song mutableCopy];[referenceInfo removeObjectForKey:@"sourceChart"];[referenceInfo removeObjectForKey:@"sourceMusic"];
 NSDictionary*compact=compactImportedSong(destination,sourceOriginal,music,converted,referenceInfo,error);if(!compact)return NO;[song addEntriesFromDictionary:compact];
 [db[@"songs"]addObject:song];[found[@"songs"]addObject:identifier];ok=[self commit:db error:error];return ok;
 }@catch(NSException*exception){if(error)*error=err(exception.reason);return NO;}@finally{if(access)[url stopAccessingSecurityScopedResource];if(!ok)for(NSString*p in moved)[f removeItemAtPath:p error:nil];if(journalPath&&ok)[f removeItemAtPath:journalPath error:nil];[f removeItemAtPath:stage error:nil];}
}

#include "PMTrashStore.inc"

- (NSURL*)exportSong:(NSString*)identifier error:(NSError**)error{NSDictionary*song=nil;for(NSDictionary*x in [self snapshot][@"songs"])if([x[@"id"]isEqualToString:identifier])song=x;if(!song){if(error)*error=err(@"Chart does not exist");return nil;}NSFileManager*f=NSFileManager.defaultManager;NSString*sourceFolder=[self asset:identifier],*stage=[[self.root stringByAppendingPathComponent:@"imports"]stringByAppendingPathComponent:NSUUID.UUID.UUIDString];@try{if(!copyTree(sourceFolder,stage,error))return nil;NSDictionary*chart=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[stage stringByAppendingPathComponent:@"chart.json"]] options:NSJSONReadingMutableContainers error:error];if(!chart)return nil;NSMutableArray*all=[NSMutableArray new];for(NSString*rel in [f subpathsOfDirectoryAtPath:stage error:nil]){BOOL dir=NO;NSString*absolute=[stage stringByAppendingPathComponent:rel];[f fileExistsAtPath:absolute isDirectory:&dir];if(!dir)[all addObject:absolute];}NSString*source=locate(all,song[@"sourceMusic"],@[@"mp3",@"ogg",@"wav",@"flac",@"m4a",@"caf",@"pcm"],YES,error);if(!prepareAndroidSongFolder(stage,chart,source,error,true))return nil;if(!writeExportInfo(stage,song,source,error))return nil;stripIOSArtifacts(stage);NSString*out=[[self.root stringByAppendingPathComponent:@"exports"]stringByAppendingPathComponent:[identifier stringByAppendingString:@".zip"]];return PMCreateArchive(stage,out,error)?[NSURL fileURLWithPath:out]:nil;}@catch(NSException*exception){if(error)*error=err(exception.reason);return nil;}@finally{[f removeItemAtPath:stage error:nil];}}
- (NSURL*)exportChapter:(NSString*)identifier error:(NSError**)error{
 NSError*failure=nil;
 NSDictionary*db=[self snapshot],*main=nil;for(NSDictionary*c in db[@"chapters"])if([c[@"id"]isEqualToString:identifier])main=c;if(!main){if(error)*error=err(@"Chapter does not exist");return nil;}
 NSFileManager*f=NSFileManager.defaultManager;NSString*stage=[[self.root stringByAppendingPathComponent:@"imports"]stringByAppendingPathComponent:NSUUID.UUID.UUIDString];if(![f createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:error])return nil;
 NSMutableDictionary*songByID=[NSMutableDictionary new],*chapterByID=[NSMutableDictionary new],*groupMembers=[NSMutableDictionary new];
 for(NSDictionary*s in storeArray(db[@"songs"])){if([s[@"id"]isKindOfClass:NSString.class])songByID[s[@"id"]]=s;NSString*g=[s[@"groupId"]isKindOfClass:NSString.class]&&[s[@"groupId"]length]?s[@"groupId"]:s[@"id"];if(g){if(!groupMembers[g])groupMembers[g]=[NSMutableArray new];[groupMembers[g]addObject:s];}}
 for(NSDictionary*c in storeArray(db[@"chapters"]))if([c[@"id"]isKindOfClass:NSString.class])chapterByID[c[@"id"]]=c;
 NSMutableArray*chapterIDs=[NSMutableArray new],*entityQueue=[NSMutableArray new],*officialIDs=[NSMutableArray new];NSMutableSet*seenChapters=[NSMutableSet new],*seenSongs=[NSMutableSet new],*seenOfficial=[NSMutableSet new];NSMutableDictionary*chapterOrders=[NSMutableDictionary new],*locations=[NSMutableDictionary new];NSMutableDictionary*loose=nil;BOOL graphLimitExceeded=NO;
 std::function<void(NSString*)> addChapter,addReference;std::function<void(NSString*,NSString*)> addSong;
 addSong=[&](NSString*sid,NSString*owner){if(!sid.length)return;if(![seenSongs containsObject:sid]&&seenSongs.count>=2000){graphLimitExceeded=YES;return;}if([seenSongs containsObject:sid]){if(owner.length){if(!locations[sid])locations[sid]=owner;if(!chapterOrders[owner])chapterOrders[owner]=[NSMutableArray new];if(![chapterOrders[owner]containsObject:sid])[chapterOrders[owner]addObject:sid];}return;}NSDictionary*s=songByID[sid];if(!s)return;[seenSongs addObject:sid];NSString*group=[s[@"groupId"]isKindOfClass:NSString.class]&&[s[@"groupId"]length]?s[@"groupId"]:sid;if(owner.length&&!locations[sid])locations[sid]=owner;if(owner.length){if(!chapterOrders[owner])chapterOrders[owner]=[NSMutableArray new];if(![chapterOrders[owner]containsObject:sid])[chapterOrders[owner]addObject:sid];}else if(!locations[sid])locations[sid]=s[@"targetChapter"]?:identifier;[entityQueue addObject:@{@"kind":@"song",@"id":sid}];for(NSDictionary*v in groupMembers[group]){NSString*vid=v[@"id"];if(![seenSongs containsObject:vid])addSong(vid,owner.length?owner:locations[sid]);}};
 addChapter=[&](NSString*cid){if(!cid.length||[seenChapters containsObject:cid])return;NSDictionary*c=chapterByID[cid];if(!c)return;if(seenChapters.count>=129){graphLimitExceeded=YES;return;}[seenChapters addObject:cid];[chapterIDs addObject:cid];if(!chapterOrders[cid])chapterOrders[cid]=[NSMutableArray new];[entityQueue addObject:@{@"kind":@"chapter",@"id":cid}];for(NSString*sid in storeArray(c[@"songs"])){if(songByID[sid])addSong(sid,cid);else if([sid isKindOfClass:NSString.class]&&sid.length){if(![seenOfficial containsObject:sid]){[seenOfficial addObject:sid];[officialIDs addObject:sid];}[chapterOrders[cid]addObject:sid];}}};
 addReference=[&](NSString*ref){if(!ref.length)return;NSArray*members=groupMembers[ref];if(members.count){for(NSDictionary*s in members){NSString*owner=s[@"targetChapter"];if(!owner.length||!chapterByID[owner]){if(!loose){loose=[@{@"id":fresh(),@"name":[NSString stringWithFormat:@"%@ ? Unlock prerequisites",main[@"name"]?:@"Chapter"],@"subtitle":@"DEPENDENCIES",@"songs":[NSMutableArray new],@"before":@""}mutableCopy];chapterByID[loose[@"id"]]=loose;[seenChapters addObject:loose[@"id"]];[chapterIDs addObject:loose[@"id"]];chapterOrders[loose[@"id"]]=[NSMutableArray new];[entityQueue addObject:@{@"kind":@"chapter",@"id":loose[@"id"]}];}owner=loose[@"id"];}else addChapter(owner);addSong(s[@"id"],owner);}return;}
 NSDictionary*s=songByID[ref];if(s){NSString*owner=s[@"targetChapter"];if(!owner.length||!chapterByID[owner]){if(!loose){loose=[@{@"id":fresh(),@"name":[NSString stringWithFormat:@"%@ ? Unlock prerequisites",main[@"name"]?:@"Chapter"],@"subtitle":@"DEPENDENCIES",@"songs":[NSMutableArray new],@"before":@""}mutableCopy];chapterByID[loose[@"id"]]=loose;[seenChapters addObject:loose[@"id"]];[chapterIDs addObject:loose[@"id"]];chapterOrders[loose[@"id"]]=[NSMutableArray new];[entityQueue addObject:@{@"kind":@"chapter",@"id":loose[@"id"]}];}owner=loose[@"id"];}else addChapter(owner);addSong(ref,owner);return;}
 if(![seenOfficial containsObject:ref]){[seenOfficial addObject:ref];[officialIDs addObject:ref];}};
 addChapter(identifier);if(![seenChapters containsObject:identifier]){[f removeItemAtPath:stage error:nil];if(error)*error=err(@"Unable to load chapter dependency plan");return nil;}
 @try{
  for(NSUInteger q=0;q<entityQueue.count;q++){@autoreleasepool{NSDictionary*token=entityQueue[q];NSString*eid=token[@"id"];NSDictionary*entity=[token[@"kind"]isEqualToString:@"chapter"]?chapterByID[eid]:songByID[eid];NSDictionary*rule=entity[@"unlock"];for(NSDictionary*c in storeArray(rule[@"conditions"])){NSString*type=c[@"type"],*ref=c[@"ref"];if([type isEqualToString:@"chapter"])addChapter(ref);else if(![type isEqualToString:@"rks"])addReference(ref);}NSDictionary*chain=rule[@"chain"];if([chain[@"enabled"]boolValue])addReference(chain[@"song"]);NSDictionary*cover=entity[@"coverSwitch"];if([cover[@"ref"]isKindOfClass:NSString.class]&&[cover[@"ref"]length])addReference(cover[@"ref"]);if(graphLimitExceeded||seenSongs.count>2000||seenChapters.count>129){failure=err(@"Chapter dependency limit exceeded");return nil;}}}
  NSMutableArray*exportSongs=[NSMutableArray new];for(NSString*sid in seenSongs){@autoreleasepool{NSDictionary*s=songByID[sid];if(!validateUnlockMedia(s,[self asset:sid],&failure))return nil;NSMutableDictionary*copy=remapUnlockEntity(s,@{},@{},@{});copy[@"previewStart"]=s[@"previewStart"]?:s[@"preview"]?:@0;copy[@"difficultyText"]=s[@"difficultyText"]?:[s[@"difficulty"]description]?:@"";if(locations[sid])copy[@"targetChapter"]=locations[sid];[exportSongs addObject:copy];NSString*dest=[[stage stringByAppendingPathComponent:@"songs"]stringByAppendingPathComponent:sid];if(![f createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]||![f copyItemAtPath:[self asset:sid] toPath:dest error:&failure])return nil;NSDictionary*chart=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dest stringByAppendingPathComponent:@"chart.json"]] options:0 error:&failure];if(!chart)return nil;NSMutableArray*assets=[NSMutableArray new];for(NSString*rel in [f subpathsOfDirectoryAtPath:dest error:nil]){BOOL dir=NO;NSString*p=[dest stringByAppendingPathComponent:rel];[f fileExistsAtPath:p isDirectory:&dir];if(!dir)[assets addObject:p];}NSString*music=locate(assets,s[@"sourceMusic"],@[@"mp3",@"ogg",@"wav",@"flac",@"m4a",@"caf",@"pcm"],YES,&failure);if(!prepareAndroidSongFolder(dest,chart,music,&failure,true))return nil;if(!writeExportInfo(dest,s,music,&failure))return nil;
 if([copy[@"sourceMusic"]isEqualToString:@"music.m4a"]||[copy[@"sourceMusic"]isEqualToString:@"music.caf"])copy[@"sourceMusic"]=[@"audio.export." stringByAppendingString:[copy[@"sourceMusic"]pathExtension]];
 stripIOSArtifacts(dest);}}
  NSMutableArray*dependencies=[NSMutableArray new];for(NSString*cid in chapterIDs){if([cid isEqualToString:identifier])continue;NSDictionary*source=chapterByID[cid];if(!source)continue;if(!validateUnlockMedia(source,[self asset:cid],&failure))return nil;NSMutableDictionary*copy=remapUnlockEntity(source,@{},@{},@{});copy[@"songs"]=chapterOrders[cid]?:@[];copy[@"before"]=identifier;[dependencies addObject:copy];NSString*from=[self asset:cid],*to=[[stage stringByAppendingPathComponent:@"chapters"]stringByAppendingPathComponent:cid];if([f fileExistsAtPath:from]){if(![f createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]||![f copyItemAtPath:from toPath:to error:&failure])return nil;}}
  if(!validateUnlockMedia(main,[self asset:identifier],&failure))return nil;NSMutableDictionary*mainCopy=remapUnlockEntity(main,@{},@{},@{});mainCopy[@"songs"]=chapterOrders[identifier]?:storeArray(main[@"songs"]);NSMutableArray*mainOrder=[mainCopy[@"songs"]mutableCopy];for(NSString*sid in storeArray(main[@"songs"]))if(![mainOrder containsObject:sid]&&([seenOfficial containsObject:sid]||[seenSongs containsObject:sid]))[mainOrder addObject:sid];mainCopy[@"songs"]=mainOrder;
  NSString*coverFolder=[self asset:identifier];if([f fileExistsAtPath:coverFolder]&&![f copyItemAtPath:coverFolder toPath:[stage stringByAppendingPathComponent:@"chapter"] error:&failure])return nil;
  for(NSString*cid in chapterIDs){NSString*folder=[cid isEqualToString:identifier]?[stage stringByAppendingPathComponent:@"chapter"]:[[stage stringByAppendingPathComponent:@"chapters"] stringByAppendingPathComponent:cid];NSString*cover=[folder stringByAppendingPathComponent:@"image.png"];if(![f fileExistsAtPath:cover]){NSString*fallback=nil;for(NSString*assetID in @[cid,identifier,@"pm_local"]){NSString*candidate=[[self asset:assetID] stringByAppendingPathComponent:@"image.png"];if([f fileExistsAtPath:candidate]){fallback=candidate;break;}}if(!fallback){failure=err(@"Chapter cover missing; assign a cover before exporting");return nil;}if(![f createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&failure]||![f copyItemAtPath:fallback toPath:cover error:&failure])return nil;}if(!validateChapterImages(folder,&failure))return nil;}
  NSMutableArray*official=[NSMutableArray new];NSMutableSet*available=[NSMutableSet new];NSDictionary*base=pmcontent::cachedOfficialSnapshot()[@"songBase"];for(NSString*key in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSDictionary*song in base[key])if(song[@"songsId"])[available addObject:song[@"songsId"]];for(NSString*sid in officialIDs)[official addObject:@{@"id":sid}];if(!PMChapterOfficialReferences(official,PMOfficialChapterEntries(pmcontent::cachedOfficialSnapshot()),&failure))return nil;NSMutableDictionary*selections=[NSMutableDictionary new];NSDictionary*allSelections=db[@"chartSelections"];for(NSString*key in allSelections)if([seenSongs containsObject:allSelections[key]])selections[key]=allSelections[key];NSMutableDictionary*manifest=[@{@"format":@"phigros-phi-chapter",@"version":@3,@"chapter":mainCopy,@"dependencyChapters":dependencies,@"songs":exportSongs,@"officialSongs":official,@"selections":selections}mutableCopy];NSMutableArray*inventory=[NSMutableArray new];for(NSString*rel in [f subpathsOfDirectoryAtPath:stage error:nil]){NSString*path=[stage stringByAppendingPathComponent:rel];BOOL dir=NO;[f fileExistsAtPath:path isDirectory:&dir];if(!dir){NSString*hash=digest(path);if(!hash){failure=err(@"Unable to read an export asset for its checksum");return nil;}[inventory addObject:@{@"path":rel,@"size":[f attributesOfItemAtPath:path error:nil][NSFileSize]?:@0,@"sha256":hash}];}}manifest[@"files"]=inventory;if(!writeJSONCompact(manifest,[stage stringByAppendingPathComponent:@"chapter.json"],&failure))return nil;NSString*out=[[self.root stringByAppendingPathComponent:@"exports"]stringByAppendingPathComponent:[identifier stringByAppendingString:@".phi-chapter.zip"]];return PMCreateArchive(stage,out,&failure)?[NSURL fileURLWithPath:out]:nil;
 }@catch(NSException*exception){failure=err(exception.reason);return nil;}@finally{if(error&&failure)*error=failure;[f removeItemAtPath:stage error:nil];}
}

- (BOOL)removeSong:(NSString*)identifier error:(NSError**)error{return [self removeSongs:@[identifier] error:error];}

@end