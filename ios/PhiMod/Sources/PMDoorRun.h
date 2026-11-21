#pragma once
#import <Foundation/Foundation.h>
BOOL PMDoorArm(NSString *chapter,NSString *door,NSString *group,int slot,NSString *chart,double hp,NSArray<NSNumber*> *delta);
BOOL PMDoorBeginTrack(NSString *group,int slot,double *hp,double delta[4]);
BOOL PMDoorBeginExactTrack(NSString *group,int slot,NSString *chart,double *hp,double delta[4]);
BOOL PMDoorActive(void);
void PMDoorFinish(BOOL clear);
void PMDoorAbandon(void);
void PMDoorCancelPending(void);
void PMDoorProgressBarrier(void);
