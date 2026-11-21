#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {int song; char title[256], caption[1024];} PMOSCard;
typedef struct {int listFirst,count; PMOSCard cards[128];char error[384];} PMOSPage;
int PMBuildOSPage(const char *source,size_t len,int songs,PMOSPage *page);
#ifdef __cplusplus
}
#endif
