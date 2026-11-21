#include "PMChapterVM.h"
#include "../Vendor/lua54/lua.h"
#include "../Vendor/lua54/lauxlib.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {size_t bytes;const char *source;size_t length;int songs;PMOSPage *out;} Session;
static void *budget(void *ctx,void *ptr,size_t old,size_t size){
 Session *s=ctx;if(!ptr)old=0;
 if(!size){free(ptr);s->bytes-=old;return NULL;}
 if(size>8*1024*1024-(s->bytes-old))return NULL;
 void *p=realloc(ptr,size);if(p)s->bytes=s->bytes-old+size;return p;
}
static Session *session(lua_State *L){void *p=NULL;lua_getallocf(L,&p);return p;}
static void limit(lua_State *L,lua_Debug *ar){(void)ar;luaL_error(L,"instruction limit exceeded");}
static int home(lua_State *L){size_t n;const char *m=luaL_checklstring(L,1,&n);if(!((n==4&&!memcmp(m,"list",4))||(n==2&&!memcmp(m,"os",2))))return luaL_error(L,"home expects os or list");session(L)->out->listFirst=!strcmp(m,"list");return 0;}
static void text(lua_State *L,int i,char *dst,size_t cap){if(lua_isnoneornil(L,i))return;size_t n=0;const char *v=luaL_checklstring(L,i,&n);if(n>=cap||memchr(v,0,n))luaL_error(L,"invalid or oversized card text");memcpy(dst,v,n);dst[n]=0;}
static int card(lua_State *L){Session *s=session(L);lua_Integer index=luaL_checkinteger(L,1);
 if(index<1||index>s->songs)return luaL_error(L,"song number outside chapter order");if(s->out->count>=128)return luaL_error(L,"too many cards");
 PMOSCard *c=&s->out->cards[s->out->count++];c->song=(int)index;text(L,2,c->title,sizeof(c->title));text(L,3,c->caption,sizeof(c->caption));return 0;}
static int evaluate(lua_State *L){Session *s=session(L);lua_pushcfunction(L,home);lua_setglobal(L,"home");lua_pushcfunction(L,card);lua_setglobal(L,"card");lua_pushinteger(L,s->songs);lua_setglobal(L,"song_count");
 if(luaL_loadbufferx(L,s->source,s->length,"@os.lua","t"))return lua_error(L);lua_sethook(L,limit,LUA_MASKCOUNT,150000);lua_call(L,0,0);return 0;}
int PMBuildOSPage(const char *src,size_t n,int songs,PMOSPage *out){memset(out,0,sizeof(*out));if(!src||!n||n>2097152||songs<0){snprintf(out->error,sizeof(out->error),"invalid OS input");return 0;}
 Session s={0,src,n,songs,out};lua_State *L=lua_newstate(budget,&s);if(!L){snprintf(out->error,sizeof(out->error),"cannot create Lua state");return 0;}
 lua_pushcfunction(L,evaluate);int ok=lua_pcall(L,0,0,0)==LUA_OK;if(!ok){const char *msg=lua_type(L,-1)==LUA_TSTRING?lua_tostring(L,-1):NULL;snprintf(out->error,sizeof(out->error),"%s",msg?msg:"script failed");out->count=0;}
 lua_close(L);return ok;}
