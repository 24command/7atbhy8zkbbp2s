#pragma once
#import <Foundation/Foundation.h>
namespace pmbridge { struct Runtime; }
namespace pmnativeosrows {
struct Row { void *row=nullptr; int slot=-1; void *cover=nullptr; };
// Main thread. entries: dictionaries with songID (installed ID) and optional difficulty.
// One handoff at a time. A failed prepare leaves lookup empty.
bool prepare(pmbridge::Runtime&,void *selector,NSString *chapter,NSArray<NSDictionary *> *entries);
// Borrowed until release or the next prepare. Pass cover to pmnativedetail::open/update.
bool lookup(NSString *installedID,NSString *difficulty,Row &out);
void release();
}
