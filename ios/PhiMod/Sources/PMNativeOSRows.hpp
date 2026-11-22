#pragma once
#import <Foundation/Foundation.h>
namespace pmbridge { struct Runtime; }
namespace pmnativeosrows {
struct Row { void *row=nullptr; int slot=-1; void *cover=nullptr; };
// Main thread. entries: dictionaries with songID (installed ID) and optional difficulty.
// Valid chapter snapshots can be empty. Unavailable entries are omitted.
// A changed content revision invalidates the batch, including subsequent lookups.
bool prepare(pmbridge::Runtime&,void *selector,NSString *chapter,NSArray<NSDictionary *> *entries);
// Borrowed until release or the next prepare. A null cover uses native official art.
bool lookup(NSString *installedID,NSString *difficulty,Row &out);
void release();
}
