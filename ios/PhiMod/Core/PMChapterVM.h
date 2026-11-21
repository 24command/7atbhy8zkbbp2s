#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {int song,speech; double seconds;char speechHeading[192];char title[256], caption[1024];} PMOSCard;
enum {PMOSFrame, PMOSImage, PMOSHotspot};
enum { PMOSMaxNodes = 256, PMOSMaxScreens = 32, PMOSScreenNameSize = 64 };
typedef struct {double x,y,w,h,start,duration,fade;int kind,parent,depth,cover,open,screen,dest,fill,loop,handler,hidden;unsigned rgba;char id[64],src[256],label[256],to[64];} PMOSNode;
typedef struct {int nodes,screens;double aspect;char names[PMOSMaxScreens][PMOSScreenNameSize];PMOSNode elements[PMOSMaxNodes];int listFirst,count; PMOSCard cards[128];char error[384];} PMOSPage;
typedef struct PMOSSession PMOSSession;
typedef struct {int song, dest, element, visible; char error[384];} PMOSAction;

/* The caller owns the source and page and may release both after start returns.
   Serialize clicks and stop for a given session. A failed start sets page->error. */
PMOSSession *PMOSStart(const char *source, size_t len, int songs, PMOSPage *page);
void PMOSStop(PMOSSession *session);
/* Pass the zero-based element index (handler is a presence flag). Static actions
   are supported too. song defaults to 0, dest and element to -1. For show/hide,
   element indexes page->elements on the clicked screen and visible is 1/0.
   Failure returns 0, clears the action and sets out->error. */
int PMOSClick(PMOSSession *session, int zeroBasedNode, PMOSAction *out);
int PMBuildOSPage(const char *source,size_t len,int songs,PMOSPage *page);
#ifdef __cplusplus
}
#endif
