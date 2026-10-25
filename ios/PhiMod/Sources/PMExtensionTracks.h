#pragma once
#import <Foundation/Foundation.h>

// Converts Phira/RPE extensions/extra.json to the Android-compatible effects.tsv format.
BOOL PMConvertExtraJSON(NSString *source, NSString *destination, NSError **error);
