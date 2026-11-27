#pragma once
#import <Foundation/Foundation.h>
// Main-thread diagnostic for a rejected OS declaration or selected story binding.
// One active alert; never navigates, changes progress, or starts a song.
void PMOSShowLoadError(NSString *message);