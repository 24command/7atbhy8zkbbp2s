#import "PMChartConvert.h"
#include "../Core/PMRPECore.hpp"
#include <set>
#include <sstream>
#include <cfloat>
using namespace phimod::rpe;
namespace {
double number(id v,double fallback=0){if(!v||v==NSNull.null)return fallback;if(![v respondsToSelector:@selector(doubleValue)])throw std::runtime_error("Invalid chart number");double x=[v doubleValue];if(!std::isfinite(x))throw std::runtime_error("Nonfinite chart number");return x;}
NSArray*array(id x){return [x isKindOfClass:NSArray.class]?x:@[];}
double beat(id v){if([v isKindOfClass:NSArray.class]){NSArray*a=v;if(a.count!=3||number(a[2])==0)throw std::runtime_error("Invalid RPE beat");return number(a[0])+number(a[1])/number(a[2]);}return number(v);}
Tempo tempo(NSArray*values){Tempo out;NSMutableArray*sorted=[values mutableCopy];[sorted sortUsingComparator:^NSComparisonResult(id a,id b){double x=beat(a[@"startTime"]),y=beat(b[@"startTime"]);return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];for(NSDictionary*v in sorted){double b=beat(v[@"startTime"]),bpm=number(v[@"bpm"]);if(bpm<=0)throw std::runtime_error("BPM must be positive");double t=out.beats.empty()?b*60/bpm:out.times.back()+(b-out.beats.back())*60/out.bpms.back();out.beats.push_back(b);out.times.push_back(t);out.bpms.push_back(bpm);}if(out.beats.empty())throw std::runtime_error("Missing BPM list");return out;}
Event event(NSDictionary*v,const Tempo&t){Event e;e.s=t.seconds(beat(v[@"startTime"]));e.e=t.seconds(beat(v[@"endTime"]));e.a=number(v[@"start"]);e.b=number(v[@"end"]);e.left=number(v[@"easingLeft"],0);e.right=number(v[@"easingRight"],1);e.easing=int(number(v[@"easingType"],1));e.bezier=number(v[@"bezier"])!=0;NSArray*p=array(v[@"bezierPoints"]);if(e.bezier){if(p.count!=4)throw std::runtime_error("Invalid Bezier control points");for(int i=0;i<4;++i)e.points[i]=number(p[i]);}if(e.e<e.s)e.e=e.s;return e;}
Track track(NSArray*input,const Tempo&t,double fallback=0){Track out;out.fallback=fallback;for(NSDictionary*v in input)out.events.push_back(event(v,t));std::stable_sort(out.events.begin(),out.events.end(),[](auto&a,auto&b){return a.s<b.s;});return out;}
NSDictionary*jsonEvent(const Linear&r){return @{ @"startTime":@(r[0]),@"endTime":@(r[1]),@"start":@(r[2]),@"end":@(r[3]),@"start2":@(r[4]),@"end2":@(r[5]) };}
NSArray*linear(const std::set<double>&cuts,const std::function<std::array<double,2>(double)>&fn,double tolerance){std::vector<Linear>events;double last=*cuts.begin();for(double end:cuts){if(end>last)subdivide(events,fn,last,end,fn(last+1e-8),fn(std::max(last,end-1e-8)),tolerance);last=end;}auto v=fn(last+1e-8);events.push_back({last*64,1e9,v[0],v[0],v[1],v[1]});NSMutableArray*out=[NSMutableArray new];for(auto&e:events)[out addObject:jsonEvent(e)];return out;}
void addCuts(const std::vector<Line>&lines,int i,std::set<double>&cuts,std::set<int>&seen,double bound){if(i<0||size_t(i)>=lines.size()||!seen.insert(i).second)return;for(int k=0;k<4;++k)for(const auto&tr:lines[i].layers[k])for(auto&e:tr.events)for(double v:{e.s,e.e})if(v>=0&&v<bound)cuts.insert(v);addCuts(lines,lines[i].parent,cuts,seen,bound);}
double floorAt(NSArray*speeds,double seconds){if(!speeds.count)return 0;NSDictionary*last=speeds.firstObject;for(NSDictionary*e in speeds){if(number(e[@"startTime"])/64>seconds)break;last=e;}return number(last[@"floorPosition"])+(seconds-number(last[@"startTime"])/64)*number(last[@"value"]);}
double speedAt(NSArray*speeds,double seconds){if(!speeds.count)return 1;NSDictionary*last=speeds.firstObject;for(NSDictionary*e in speeds){if(number(e[@"startTime"])/64>seconds)break;last=e;}return number(last[@"value"]);}
NSArray*normalEvents(NSArray*input,const Tempo&t){NSMutableArray*out=[NSMutableArray new];for(NSDictionary*v in input){NSMutableDictionary*e=[v mutableCopy];e[@"startTime"]=@(t.seconds(beat(v[@"startTime"])));e[@"endTime"]=@(t.seconds(beat(v[@"endTime"])));[out addObject:e];}return out;}
NSDictionary*rpe(NSDictionary*input){
 NSArray*source=array(input[@"judgeLineList"]);if(!source.count||source.count>2048)throw std::runtime_error("RPE line count must be 1-2048");
 Tempo global=tempo(array(input[@"BPMList"]));
 std::vector<Tempo>tempos;std::vector<Line>lines;double bound=1;int count=0;
 double mediaDuration=number(input[@"META"][@"duration"],0);if(std::isfinite(mediaDuration)&&mediaDuration>0)bound=mediaDuration;
 for(NSDictionary*o in source){
  Tempo t=global;t.factor=number(o[@"bpmfactor"],1);if(t.factor<=0)throw std::runtime_error("Invalid line BPM factor");tempos.push_back(t);
  Line line;line.parent=int(number(o[@"father"],-1));line.rotateParent=[o[@"rotateWithFather"] boolValue];
  NSString*keys[]={@"moveXEvents",@"moveYEvents",@"rotateEvents",@"alphaEvents",@"speedEvents"};
  for(NSDictionary*layer in array(o[@"eventLayers"]))
   if([layer isKindOfClass:NSDictionary.class])
    for(int k=0;k<5;++k){
     NSArray*events=array(layer[keys[k]]);
     if(!events.count)continue;
     Track tr=track(events,t,0);
     // Phira/ts parity: before the first event, alpha must hold the first
     // event's value and speed must hold its first value. A zero fallback
     // makes lines invisible and collapses every Hold body to length 0.
     if((k==3||k==4)&&!tr.events.empty())tr.fallback=tr.events.front().a;
     line.layers[k].push_back(std::move(tr));
    }
  // RPE channel defaults when a layer has no events at all:
  // alpha=255 (visible), speed=1.0 (normal), move/rotate=0.
  for(int k=0;k<5;++k)if(line.layers[k].empty()){
   Track def;def.fallback=(k==3)?255.0:(k==4)?1.0:0.0;
   line.layers[k].push_back(std::move(def));
  }
  lines.push_back(line);
  for(NSDictionary*n in array(o[@"notes"])){bound=std::max(bound,t.seconds(beat(n[@"endTime"]))+2);if(++count>100000)throw std::runtime_error("Chart exceeds 100000 notes");}
 }
 for(const auto&line:lines)for(int k=0;k<5;++k)for(const auto&tr:line.layers[k])for(const auto&e:tr.events)if(std::isfinite(e.e)&&e.e>0&&e.e<1000000.0/64.0)bound=std::max(bound,e.e);
 if(mediaDuration>0)bound=std::max(bound,mediaDuration);
 NSMutableArray*out=[NSMutableArray new];
 for(size_t i=0;i<lines.size();++i){
  const auto&l=lines[i];const auto&t=tempos[i];NSDictionary*o=source[i];
  std::set<double>cuts{0,bound};std::set<int>seen;addCuts(lines,int(i),cuts,seen,bound);
  auto poseAt=[&](double now){std::vector<bool>vis(lines.size());return pose(lines,int(i),now,vis);};
  NSArray*move=linear(cuts,[&](double now){auto p=poseAt(now);return std::array<double,2>{p[0]/1350+.5,p[1]/900+.5};},.0003);
  NSArray*rotate=linear(cuts,[&](double now){auto p=poseAt(now);return std::array<double,2>{p[2],0};},.06);
  // Phira/ts parity: alpha comes purely from alphaEvents. attachUI is a
  // hint for external UI bindings, not a request to hide the judge line.
  // Retain signed source alpha separately: zero hides only the line, negative
  // alpha hides notes as well. Native Phigros alpha must remain clamped.
  NSArray*signedAlpha=linear(cuts,[&](double now){return std::array<double,2>{l.value(3,now)/255,0};},.002);
  NSMutableArray*alpha=[NSMutableArray new];for(NSDictionary*event in signedAlpha){NSMutableDictionary*safe=[event mutableCopy];safe[@"start"]=@(std::clamp(number(event[@"start"]),0.,1.));safe[@"end"]=@(std::clamp(number(event[@"end"]),0.,1.));[alpha addObject:safe];}
  std::set<double>speedCuts{0,bound};for(const auto&tr:l.layers[4])for(auto&e:tr.events)for(double x:{e.s,e.e})if(x>=0&&x<bound)speedCuts.insert(x);
  NSMutableArray*speeds=[NSMutableArray new];double previous=0,floor=0;
  for(double end:speedCuts){
   if(end<=previous)continue;
   int parts=std::max(1,int(ceil((end-previous)*60)));
   double first=l.value(4,previous+1e-8),last=l.value(4,end-1e-8);
   if(fabs(first-last)<1e-9&&fabs(l.value(4,(previous+end)/2)-first)<1e-9&&fabs(l.value(4,previous+(end-previous)*.25)-first)<1e-9&&fabs(l.value(4,previous+(end-previous)*.75)-first)<1e-9)parts=1;
   for(int j=0;j<parts;++j){
    double a=previous+(end-previous)*j/parts,b=previous+(end-previous)*(j+1)/parts,v=l.value(4,(a+b)/2)/4.5;
    [speeds addObject:@{@"startTime":@(a*64),@"endTime":@(b*64),@"value":@(v),@"floorPosition":@(floor)}];floor+=(b-a)*v;
   }
   previous=end;
  }
  [speeds addObject:@{@"startTime":@(bound*64),@"endTime":@1e9,@"value":@(l.value(4,bound)/4.5),@"floorPosition":@(floor)}];
  NSMutableArray*above=[NSMutableArray new],*below=[NSMutableArray new];
  for(NSDictionary*n in array(o[@"notes"])){
   int type=int(number(n[@"type"]));if(type<1||type>4)throw std::runtime_error("Invalid RPE note type");
   int types[]={0,1,3,4,2},nativeType=types[type];
   double start=t.seconds(beat(n[@"startTime"])),end=t.seconds(beat(n[@"endTime"])),raw=number(n[@"speed"],1),size=number(n[@"size"],1);
   if(end<start)end=start;
   if(start<0||!std::isfinite(size)||std::fabs(size)>FLT_MAX)throw std::runtime_error("Invalid RPE note timing/size");
   // Phira/ts parity: RPE treats negative alpha as "default visible" and
   // non-positive visibleTime as "unbounded"; keeping them as-is makes the
   // note permanently invisible under the render path.
   double noteAlpha=number(n[@"alpha"],255);
   if(noteAlpha<0)noteAlpha=255;
   double noteVisible=number(n[@"visibleTime"],999999);
   if(noteVisible<=0)noteVisible=999999;
   NSMutableDictionary*note=[@{ @"type":@(nativeType),@"time":@(llround(start*64)),@"holdTime":@(nativeType==3?(end-start)*64:0),@"positionX":@(number(n[@"positionX"])/75),@"speed":@(nativeType==3?raw*speedAt(speeds,std::round(start*64.0)/64.0):raw),@"floorPosition":@(floorAt(speeds,start)),@"pmTime":@(start),@"pmDuration":@(end-start),@"pmSize":@(size),@"pmFake":@([n[@"isFake"] boolValue]),@"pmAlpha":@(std::clamp(noteAlpha/255,0.,1.)),@"pmVisible":@(noteVisible),@"pmRawSpeed":@(raw),@"pmYOffset":@(number(n[@"yOffset"])),@"pmEndFloor":@(floorAt(speeds,end)) } mutableCopy];
   [(number(n[@"above"],1)==1?above:below) addObject:note];
  }
  NSComparator byFloor=^NSComparisonResult(id a,id b){double x=number(a[@"floorPosition"]),y=number(b[@"floorPosition"]);return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;};
  [above sortUsingComparator:byFloor];[below sortUsingComparator:byFloor];
  NSMutableDictionary*decor=[NSMutableDictionary new];NSDictionary*extended=o[@"extended"];
  for(NSString*key in @[@"scaleXEvents",@"scaleYEvents",@"colorEvents",@"textEvents",@"inclineEvents"])decor[key]=normalEvents(array(extended[key]),t);
  for(NSString*key in @[@"alphaControl",@"sizeControl",@"posControl",@"yControl",@"skewControl"])decor[key]=array(o[key]);
  decor[@"Texture"]=o[@"Texture"] ?: @"line.png";
  decor[@"anchor"]=array(o[@"anchor"]).count==2?o[@"anchor"]:@[@0.5,@0.5];
  decor[@"zOrder"]=o[@"zOrder"] ?: @0;
  decor[@"isCover"]=o[@"isCover"] ?: @1;
  decor[@"attachUI"]=o[@"attachUI"] ?: @"";
  decor[@"sourceAlphaEvents"]=signedAlpha;
  [out addObject:@{ @"bpm":@120,@"notesAbove":above,@"notesBelow":below,@"speedEvents":speeds,@"judgeLineMoveEvents":move,@"judgeLineRotateEvents":rotate,@"judgeLineDisappearEvents":alpha,@"pmDecor":decor }];
 }
 return @{ @"formatVersion":@3,@"offset":@(number(input[@"META"][@"offset"])/1000),@"judgeLineList":out,@"blockAreaList":@[],@"pmFormat":@"RPE" };
}
void validate(NSDictionary*c){NSArray*lines=array(c[@"judgeLineList"]);if(!lines.count||lines.count>2048||number(c[@"formatVersion"],3)!=3)throw std::runtime_error("Supports Phigros v3 JSON, PEC and RPE");size_t notes=0,events=0;for(NSDictionary*l in lines){if(number(l[@"bpm"])<=0)throw std::runtime_error("Invalid BPM");for(NSString*key in @[@"notesAbove",@"notesBelow"]){for(NSDictionary*n in array(l[key])){int type=int(number(n[@"type"]));if(type<1||type>4||number(n[@"time"])<0||number(n[@"holdTime"])<0)throw std::runtime_error("Invalid note");if(![n[@"pmFake"] boolValue])++notes;}}for(NSString*key in @[@"speedEvents",@"judgeLineMoveEvents",@"judgeLineRotateEvents",@"judgeLineDisappearEvents"]){NSArray*track=array(l[key]);if(!track.count)throw std::runtime_error("Missing chart event track");double last=-1e99;for(NSDictionary*e in track){double s=number(e[@"startTime"]),end=number(e[@"endTime"]);if(s<last-.001||end<s)throw std::runtime_error("Invalid chart event ordering");last=end;if(++events>2000000)throw std::runtime_error("Chart exceeds two million events");}}}if(!notes||notes>100000)throw std::runtime_error("Chart has no scoring notes or too many notes");}
NSDictionary*pec(NSString*text){
 struct Cmd{NSString*op;std::vector<double>v;};
 std::vector<Cmd>cmds;std::vector<std::pair<double,double>>bp;
 int maxId=0,total=0;NSArray*rows=[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
 double offset=0;BOOL readOffset=NO;
 auto parseNumber=[](NSString*t){NSScanner*s=[NSScanner scannerWithString:t];s.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];double n=0;if(![s scanDouble:&n]||!s.isAtEnd||!std::isfinite(n))throw std::runtime_error("Invalid PEC number");return n;};
 for(NSUInteger row=0;row<rows.count;++row){NSString*raw=rows[row];NSArray*parts=[raw componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSMutableArray*tokens=[NSMutableArray new];for(NSString*t in parts)if(t.length)[tokens addObject:t];if(!tokens.count)continue;
  if(!readOffset){if(tokens.count!=1)throw std::runtime_error("PEC offset is invalid");offset=parseNumber(tokens[0]);readOffset=YES;continue;}
  for(NSUInteger begin=0;begin<tokens.count;){NSString*op=tokens[begin++];NSUInteger stop=begin;while(stop<tokens.count&&![tokens[stop]isEqualToString:@"#"]&&![tokens[stop]isEqualToString:@"&"])++stop;std::vector<double>v;for(NSUInteger i=begin;i<stop;++i)v.push_back(parseNumber(tokens[i]));
   int expected=[op isEqualToString:@"bp"]?2:[op isEqualToString:@"n2"]?6:([@[@"n1",@"n3",@"n4"]containsObject:op]?5:[op isEqualToString:@"cp"]?4:[op isEqualToString:@"cm"]?6:[op isEqualToString:@"cr"]?5:[op isEqualToString:@"cf"]?4:[@[@"cv",@"cd",@"ca"]containsObject:op]?3:[@[@"#",@"&"]containsObject:op]?1:-1);
   if(expected<0||v.size()!=size_t(expected))throw std::runtime_error("Unsupported PEC command or argument count");
   if([op isEqualToString:@"bp"]){if(v[1]<=0)throw std::runtime_error("PEC BPM must be positive");bp.push_back({v[0],v[1]});}
   else{if(![@[@"#",@"&"]containsObject:op]){if(v[0]<0||v[0]>2047||floor(v[0])!=v[0])throw std::runtime_error("PEC judge line id must be 0-2047");maxId=std::max(maxId,int(v[0]));}cmds.push_back({op,std::move(v)});}
   begin=stop;
  }
 }
 if(!readOffset)throw std::runtime_error("PEC offset is missing");
 if(bp.empty())throw std::runtime_error("PEC BPM list is empty");
 std::stable_sort(bp.begin(),bp.end(),[](auto&a,auto&b){return a.first<b.first;});
 if(bp.front().first>0)bp.insert(bp.begin(),{0,bp.front().second});
 auto ticks=[&](double beatValue){double seconds=0;for(size_t i=0;i<bp.size();++i){double from=bp[i].first,to=i+1<bp.size()?bp[i+1].first:beatValue;if(beatValue<=from)break;seconds+=(std::min(beatValue,to)-from)*60/bp[i].second;if(beatValue<=to)break;}return seconds*64;};
 auto eventJSON=[](double start,double end,double x0,double x1,double y0,double y1)->NSDictionary*{return @{@"startTime":@(start),@"endTime":@(end),@"start":@(x0),@"end":@(x1),@"start2":@(y0),@"end2":@(y1)};};
 std::function<void(NSMutableArray*,double,double,double,double,double,double,double,double,int,int,int)> curve;
 curve=[&](NSMutableArray*out,double start,double end,double x0,double x1,double y0,double y1,double p,double q,int easing,int kind,int depth){
  double a=phimod::rpe::ease(easing,p),b=phimod::rpe::ease(easing,q),error=0;
  if(easing>1&&depth<14)for(double f:{.25,.5,.75}){double t=p+(q-p)*f;error=std::max(error,std::fabs(phimod::rpe::ease(easing,t)-(a+(b-a)*f)));}
  double tolerance=kind==0?.0002:kind==1?.025:.001;
  if(error*std::max(std::fabs(x1-x0),std::fabs(y1-y0))>tolerance){double mid=(p+q)*.5;curve(out,start,end,x0,x1,y0,y1,p,mid,easing,kind,depth+1);curve(out,start,end,x0,x1,y0,y1,mid,q,easing,kind,depth+1);return;}
  if(out.count>=2000000)throw std::runtime_error("PEC converted event count exceeds two million");
  [out addObject:eventJSON(start+(end-start)*p,start+(end-start)*q,x0+(x1-x0)*a,x0+(x1-x0)*b,y0+(y1-y0)*a,y0+(y1-y0)*b)];
 };
 auto events=[&](std::vector<Cmd> changes,int kind){
  auto isInstant=[](NSString*op){return [@[@"cp",@"cd",@"ca"]containsObject:op];};
  std::stable_sort(changes.begin(),changes.end(),[&](const Cmd&a,const Cmd&b){double ae=isInstant(a.op)?a.v[1]:a.v[2],be=isInstant(b.op)?b.v[1]:b.v[2];return ae==be?a.v[1]<b.v[1]:ae<be;});
  NSMutableArray*out=[NSMutableArray new];double x=kind==0?.5:kind==2?1:0,y=kind==0?.5:0,at=0;
  for(const auto&cmd:changes){const auto&v=cmd.v;double start=std::max(at,ticks(v[1]));if(start>at)[out addObject:eventJSON(at,start,x,x,y,y)];bool instant=isInstant(cmd.op);double end=instant?start:ticks(v[2]);if(end<start)throw std::runtime_error("PEC event ends before start");
   double nx=kind==0?v[instant?2:3]/2048:kind==1?-v[instant?2:3]:v[instant?2:3]/255;
   double ny=kind==0?v[instant?3:4]/1400:0;int easing=instant?0:kind==2?1:int(v.back());if(easing<0||easing>29)throw std::runtime_error("Unsupported PEC easing");
   if(end>start)curve(out,start,end,x,nx,y,ny,0,1,easing,kind,0);x=nx;y=ny;at=end;
  }
  [out addObject:eventJSON(at,1e9,x,x,y,y)];return out;
 };
 NSMutableArray*lines=[NSMutableArray new];
 for(int lineId=0;lineId<=maxId;++lineId){
  NSMutableArray*above=[NSMutableArray new],*below=[NSMutableArray new],*speeds=[NSMutableArray new];
  std::vector<Cmd>speedCmd,move,rotate,alpha;NSMutableDictionary*last=nil;
  for(const auto&cmd:cmds){const auto&v=cmd.v;
   if([cmd.op isEqualToString:@"#"]){if(last)last[@"speed"]=@(v[0]);continue;}
   if([cmd.op isEqualToString:@"&"]){if(!std::isfinite(v[0])||std::fabs(v[0])>FLT_MAX)throw std::runtime_error("PEC note size is invalid");if(last)last[@"pmSize"]=@(v[0]);continue;}
   if(int(v[0])!=lineId){last=nil;continue;}
   if([cmd.op hasPrefix:@"n"]){bool hold=[cmd.op isEqualToString:@"n2"];int type=[cmd.op isEqualToString:@"n1"]?1:hold?3:[cmd.op isEqualToString:@"n3"]?4:2;double time=ticks(v[1]),duration=hold?std::max(0.,ticks(v[2])-time):0;if(time<0||!std::isfinite(time))throw std::runtime_error("Invalid PEC note time");
    last=[@{@"type":@(type),@"time":@(llround(time)),@"holdTime":@(llround(duration)),@"pmSourceTime":@(time/64),@"pmSourceDuration":@(duration/64),@"pmTime":@(time/64),@"pmDuration":@(duration/64),@"positionX":@(v[hold?3:2]/115.2),@"speed":@1,@"pmFake":@(v[hold?5:4]!=0),@"pmSize":@1}mutableCopy];
    [(v[hold?4:3]==1?above:below)addObject:last];++total;
   }else if([cmd.op isEqualToString:@"cv"])speedCmd.push_back(cmd);
   else if([@[@"cp",@"cm"]containsObject:cmd.op])move.push_back(cmd);
   else if([@[@"cd",@"cr"]containsObject:cmd.op])rotate.push_back(cmd);
   else alpha.push_back(cmd);
  }
  std::stable_sort(speedCmd.begin(),speedCmd.end(),[](const Cmd&a,const Cmd&b){return a.v[1]<b.v[1];});
  double cursor=0,floorPosition=0,speed=1;
  for(const auto&cmd:speedCmd){double end=std::max(cursor,ticks(cmd.v[1]));if(end>cursor){[speeds addObject:@{@"startTime":@(cursor),@"endTime":@(end),@"value":@(speed),@"floorPosition":@(floorPosition)}];floorPosition+=(end-cursor)/64*speed;}cursor=end;speed=cmd.v[2]/7.;}
  [speeds addObject:@{@"startTime":@(cursor),@"endTime":@1e9,@"value":@(speed),@"floorPosition":@(floorPosition)}];
  auto floorAt=[&](double t){double result=0;for(NSDictionary*e in speeds){double begin=[e[@"startTime"]doubleValue],end=[e[@"endTime"]doubleValue];if(t<begin)break;result=[e[@"floorPosition"]doubleValue]+(std::min(t,end)-begin)/64*[e[@"value"]doubleValue];}return result;};
  auto speedAt=[&](double t){double result=1;for(NSDictionary*e in speeds){if(t<[e[@"startTime"]doubleValue])break;result=[e[@"value"]doubleValue];}return result;};
  for(NSMutableArray*notes in @[above,below]){for(NSMutableDictionary*n in notes){double t=[n[@"pmSourceTime"]doubleValue]*64,raw=[n[@"speed"]doubleValue],localSpeed=speedAt(t);n[@"floorPosition"]=@(floorAt(t));n[@"pmRawSpeed"]=@(raw);n[@"pmEndFloor"]=@(floorAt(t+[n[@"pmSourceDuration"]doubleValue]*64));if([n[@"type"]intValue]==3)n[@"speed"]=@(std::fabs(raw*localSpeed)<1e-6?1:raw*localSpeed);}
   [notes sortUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){double x=[a[@"time"]doubleValue],y=[b[@"time"]doubleValue];return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];
  }
  [lines addObject:@{@"bpm":@120,@"notesAbove":above,@"notesBelow":below,@"speedEvents":speeds,@"judgeLineMoveEvents":events(move,0),@"judgeLineRotateEvents":events(rotate,1),@"judgeLineDisappearEvents":events(alpha,2)}];
 }
 if(!total)throw std::runtime_error("PEC has no notes");
 return @{@"formatVersion":@3,@"offset":@((offset-175)/1000),@"pmFormat":@"PEC",@"judgeLineList":lines,@"blockAreaList":@[]};
}

NSMutableDictionary*annotateChart(NSDictionary*c){
 NSData*d=[NSJSONSerialization dataWithJSONObject:c options:0 error:nil];NSMutableDictionary*out=d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;if(!out)return nil;
 NSMutableArray*w=[out[@"pmWarnings"] isKindOfClass:NSArray.class]?[out[@"pmWarnings"] mutableCopy]:[NSMutableArray new];NSUInteger real=0,fake=0;NSMutableArray*textures=[NSMutableArray new];
 for(NSMutableDictionary*line in array(out[@"judgeLineList"])){
  NSDictionary*decor=[line[@"pmDecor"] isKindOfClass:NSDictionary.class]?line[@"pmDecor"]:nil;NSString*texture=[decor[@"Texture"] isKindOfClass:NSString.class]?decor[@"Texture"]:@"line.png";if(texture.length&&![texture isEqualToString:@"line.png"]&&! [textures containsObject:texture])[textures addObject:texture];
  for(NSString*side in @[@"notesAbove",@"notesBelow"])for(NSDictionary*n in array(line[side])){if([n[@"pmFake"] boolValue])fake++;else real++;}
 }
 out[@"pmWarnings"]=w;out[@"pmRealNotes"]=@(real);out[@"pmFakeNotes"]=@(fake);out[@"pmLineTextures"]=textures;return out;
}
} // namespace
NSDictionary*PMConvertChart(NSData*data,NSError**error){try{NSString*text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];text=[[text stringByReplacingOccurrencesOfString:@"\ufeff" withString:@""]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!text.length)throw std::runtime_error("Chart text is empty or not UTF-8");NSDictionary*c;if([text hasPrefix:@"{"]){id json=[NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:error];if(![json isKindOfClass:NSDictionary.class])return nil;c=json[@"BPMList"]?rpe(json):json;}else c=pec(text);NSMutableDictionary*annotated=annotateChart(c);if(!annotated)throw std::runtime_error("Chart metadata serialization failed");validate(annotated);return annotated;}catch(const std::exception&e){if(error)*error=[NSError errorWithDomain:@"PhiMod.Chart" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:e.what()]}];return nil;}}
NSDictionary*PMNativeChart(NSDictionary*chart){
 NSMutableArray*lines=[NSMutableArray new];
 for(NSDictionary*line in chart[@"judgeLineList"]){
  NSMutableDictionary*l=[NSMutableDictionary new];l[@"bpm"]=line[@"bpm"];
  for(NSString*key in @[@"speedEvents",@"judgeLineDisappearEvents",@"judgeLineMoveEvents",@"judgeLineRotateEvents"])l[key]=line[key] ?: @[];
  for(NSString*side in @[@"notesAbove",@"notesBelow"]){NSMutableArray*notes=[NSMutableArray new];
   for(NSDictionary*n in line[side])if(![n[@"pmFake"] boolValue]){NSMutableDictionary*note=[NSMutableDictionary new];
    for(NSString*key in @[@"type",@"time",@"positionX",@"holdTime",@"speed",@"floorPosition"])if(n[key])note[key]=n[key];
    [notes addObject:note];
   }l[side]=notes;
  }[lines addObject:l];
 }
 return @{@"formatVersion":chart[@"formatVersion"] ?: @3,@"offset":chart[@"offset"] ?: @0,@"judgeLineList":lines,@"blockAreaList":chart[@"blockAreaList"] ?: @[]};
}