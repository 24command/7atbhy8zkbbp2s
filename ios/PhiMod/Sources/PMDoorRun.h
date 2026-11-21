#pragma once
#import <Foundation/Foundation.h>
BOOL PMDoorArm(NSString *chapter,NSString *door,NSString *group,int slot,NSString *chart,double hp,NSArray<NSNumber*> *delta);
BOOL PMDoorBeginTrack(NSString *group,int slot,double *hp,double delta[4]);
BOOL PMDoorBeginExactTrack(NSString *group,int slot,NSString *chart,double *hp,double delta[4]);
BOOL PMDoorActive(void);
BOOL PMDoorSetPendingNoPause(BOOL value);
BOOL PMDoorPlayingNoPause(void);
// Checked non-HP launch; consumes a one-shot identity without creating a door run.
BOOL PMDoorArmReplay(NSString *group,int slot,NSString *chart);
BOOL PMDoorConsumeReplay(NSString *group,int slot,NSString *chart);
BOOL PMDoorReplayPending(void);
void PMDoorFinish(BOOL clear);
// Use the same outcome writer and barrier for an independently verified native course.
void PMDoorRecordCourseOutcome(NSString *chapter, NSString *door, int launchedTier, BOOL clear);
void PMDoorAbandon(void);
void PMDoorCancelPending(void);
void PMDoorProgressBarrier(void);
