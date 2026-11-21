// The chapter VM never exposes native views or filesystem paths to scripts.
#include <math.h>
static void word(lua_State *L,int index,char *out,size_t cap){
 size_t n;luaL_checktype(L,index,LUA_TSTRING);const char *s=lua_tolstring(L,index,&n);
 if(!n||n>=cap||memchr(s,0,n))luaL_error(L,"empty or oversized layout string");memcpy(out,s,n);out[n]=0;
}
static void fieldText(lua_State *L,const char *key,char *buf,size_t cap){lua_getfield(L,1,key);if(!lua_isnil(L,-1))word(L,-1,buf,cap);lua_pop(L,1);}
static int fieldBool(lua_State *L,const char *key){
 lua_getfield(L,1,key);
 if(!lua_isnil(L,-1)&&!lua_isboolean(L,-1))luaL_error(L,"%s expects true or false",key);
 int value=lua_toboolean(L,-1);lua_pop(L,1);return value;
}
// A missing timing field defaults to zero. Zero duration leaves the end open.
static double secondsField(lua_State *L, const char *key) {
    lua_getfield(L, 1, key);
    double seconds = 0;
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TNUMBER);
        seconds = lua_tonumber(L, -1);
        if (!isfinite(seconds) || seconds < 0) luaL_error(L, "invalid seconds in %s", key);
    }
    lua_pop(L, 1);
    return seconds;
}
static double axis(lua_State *L,const char *key,double def,int size){lua_getfield(L,1,key);double v=luaL_optnumber(L,-1,def);lua_pop(L,1);if(!(v>=-4 && v<=4) || (size&&v<=0))luaL_error(L,"invalid coordinate: %s",key);return v;}
static int songField(lua_State *L,const char *key){lua_getfield(L,1,key);int res=0;if(!lua_isnil(L,-1)){lua_Integer i=luaL_checkinteger(L,-1);if(i<1||i>session(L)->songs)luaL_error(L,"invalid song number in %s",key);res=(int)i;}lua_pop(L,1);return res;}
static int setCanvas(lua_State *L){PMOSPage *p=declarationPage(L);double w=luaL_checknumber(L,1),h=luaL_checknumber(L,2);if(!(w>0&&h>0&&w/h>=0.125&&w/h<=8))return luaL_error(L,"invalid canvas aspect ratio");p->aspect=w/h;return 0;}
static int screen(lua_State *L){PMOSPage *p=declarationPage(L);char name[64];word(L,1,name,sizeof(name));
 if(p->screens>=PMOSMaxScreens)return luaL_error(L,"too many screens");for(int i=0;i<p->screens;i++)if(!strcmp(p->names[i],name))return luaL_error(L,"duplicate screen: %s",name);
 strcpy(p->names[p->screens++],name);return 0;}
static int layoutNode(lua_State *L){PMOSPage *p=declarationPage(L);luaL_checktype(L,1,LUA_TTABLE);if(p->nodes>=PMOSMaxNodes)return luaL_error(L,"too many layout elements");
 if(!p->screens)strcpy(p->names[p->screens++],"main");
 int pos=p->nodes;PMOSNode *n=&p->elements[pos];n->kind=(int)lua_tointeger(L,lua_upvalueindex(1));n->screen=p->screens-1;n->parent=n->dest=-1;
 n->hidden=fieldBool(L,"hidden");
 n->start=secondsField(L,"start");
 n->duration=secondsField(L,"duration");
 n->fade=secondsField(L,"fade");
 if(!isfinite(n->start+(n->duration>0?n->duration:n->fade)))return luaL_error(L,"timing window too large");
 n->x=axis(L,"x",0,0);n->y=axis(L,"y",0,0);n->w=axis(L,"w",1,1);n->h=axis(L,"h",1,1);
 char color[12]={0};fieldText(L,"color",color,sizeof(color));if(color[0]){
  size_t len=strlen(color);if(color[0]!='#'||(len!=7&&len!=9)||strspn(color+1,"0123456789abcdefABCDEF")!=len-1)return luaL_error(L,"color expects #RRGGBB or #RRGGBBAA");
  unsigned val=(unsigned)strtoul(color+1,NULL,16);n->rgba=len==7?(val<<8)|255:val;
 }
 char parent[64]={0},fit[16]={0};fieldText(L,"id",n->id,sizeof(n->id));fieldText(L,"parent",parent,sizeof(parent));fieldText(L,"label",n->label,sizeof(n->label));fieldText(L,"to",n->to,sizeof(n->to));n->open=songField(L,"open");
 for(int i=0;i<pos;i++){PMOSNode *prev=&p->elements[i];if(prev->screen!=n->screen)continue;
  if(n->id[0]&&!strcmp(prev->id,n->id))return luaL_error(L,"duplicate element: %s",n->id);
  if(parent[0]&&!strcmp(prev->id,parent)&&prev->kind==PMOSFrame){n->parent=i;n->depth=prev->depth+1;}}
 if((parent[0]&&n->parent<0)||n->depth>8)return luaL_error(L,"missing parent frame or nesting too deep: %s",parent);
 n->challenge=challengeBindingRef(L,1);
 if(n->challenge&&(n->open||n->to[0]))return luaL_error(L,"challenge cannot be combined with open or to");
 if(n->open&&n->to[0])return luaL_error(L,"choose either open or to");
 if(n->kind==PMOSImage){n->cover=songField(L,"cover");fieldText(L,"src",n->src,sizeof(n->src));if(!!n->cover==!!n->src[0])return luaL_error(L,"image needs exactly one of src or cover");
  if(n->src[0]&&(n->src[0]=='.'||strpbrk(n->src,"/\\:")))return luaL_error(L,"src must be a local media filename");
  n->loop=fieldBool(L,"loop");
  fieldText(L,"fit",fit,sizeof(fit));if(fit[0]&&strcmp(fit,"contain")&&strcmp(fit,"cover"))return luaL_error(L,"fit expects contain or cover");n->fill=!strcmp(fit,"cover");}
 lua_getfield(L,1,"onClick");
 if(!lua_isnil(L,-1)){
  if(!lua_isfunction(L,-1))return luaL_error(L,"onClick expects a function");
  if(n->challenge)return luaL_error(L,"challenge cannot be combined with onClick");
  if(n->open||n->to[0])return luaL_error(L,"onClick cannot be combined with open or to");
  session(L)->clicks[pos].ref=luaL_ref(L,LUA_REGISTRYINDEX);
  n->handler=1;
 }else lua_pop(L,1);
 if(n->kind==PMOSHotspot&&!n->open&&!n->to[0]&&!n->handler&&!n->challenge)return luaL_error(L,"hotspot needs open, to, onClick or challenge");
 p->nodes++;return 0;}
static void resolveLinks(lua_State *L){PMOSPage *p=declarationPage(L);for(int i=0;i<p->nodes;i++){PMOSNode *n=&p->elements[i];if(!n->to[0])continue;
 n->dest=findScreen(p->names,p->screens,n->to);if(n->dest<0)luaL_error(L,"unknown target screen: %s",n->to);}}
static void registerLayout(lua_State *L){const char *names[]={"frame","image","hotspot"};for(int i=0;i<3;i++){lua_pushinteger(L,i);lua_pushcclosure(L,layoutNode,1);lua_setglobal(L,names[i]);}
 lua_pushcfunction(L,setCanvas);lua_setglobal(L,"canvas");lua_pushcfunction(L,screen);lua_setglobal(L,"screen");}
