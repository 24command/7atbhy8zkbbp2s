#pragma once
#import <Foundation/Foundation.h>
#include <cmath>
static inline NSString*PMDifficultyName(id value){NSString*s=[value isKindOfClass:NSString.class]?value:@"IN";s=[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];return s.length?s:@"IN";}
static inline int PMStockDifficulty(id value){NSString*s=PMDifficultyName(value).uppercaseString;NSUInteger i=[@[@"EZ",@"HD",@"IN",@"AT"]indexOfObject:s];return i==NSNotFound?-1:(int)i;}
static inline double PMDifficultyNumber(id value){NSString*s=[value respondsToSelector:@selector(description)]?[value description]:@"";NSScanner*scanner=[NSScanner scannerWithString:s];double n=0;return [scanner scanDouble:&n]&&scanner.isAtEnd&&std::isfinite(n)&&n>=0?n:0;}
static inline NSString*PMDifficultyText(NSDictionary*s){id v=s[@"difficultyText"]?:s[@"difficulty"];return v?[v description]:@"";}
static inline NSArray<NSNumber*>*PMDifficultyRGB(id input){
 if(![input isKindOfClass:NSString.class])return nil;
 NSString*s=[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!s.length)return @[];
 NSArray*parts=[s componentsSeparatedByString:@","];if(parts.count!=3)return nil;NSMutableArray*out=[NSMutableArray new];
 for(NSString*part in parts){NSScanner*scanner=[NSScanner scannerWithString:[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];int n;if(![scanner scanInt:&n]||!scanner.isAtEnd||n<0||n>255)return nil;[out addObject:@(n)];}return out;
}
static inline NSString*PMDifficultyRecordLevel(NSDictionary*s){int slot=PMStockDifficulty(s[@"level"]);return slot<0?@"AT":@[@"EZ",@"HD",@"IN",@"AT"][slot];}

// A native AT transport slot never implies that another song has this extra chart.
template<class Charts> static inline NSDictionary*PMMatchingExtraDifficulty(const Charts&charts,NSString*name){
 if(!name.length)return nil;
 for(NSDictionary*chart:charts)if(PMStockDifficulty(chart[@"level"])<0&&[PMDifficultyName(chart[@"level"])isEqualToString:name])return chart;
 return nil;
}
