// Reuse the game's actual setting prefab factories and layout functions.
namespace {
uint32_t nativeSettingsRoot=0;P nativeSettingsManager=nullptr;bool nativeAdvanced=false;
struct NativeOption{P item;NSString*key;float last;bool slider;};std::vector<NativeOption>nativeOptions;std::map<P,int>nativeActions;
void clearNativeSettings(Runtime&r){nativeOptions.clear();nativeActions.clear();nativeSettingsManager=nullptr;nativeAdvanced=false;dispose(r,nativeSettingsRoot,true);}
P nativeTitle(Runtime&r,NSString*text){P title=r.object_new(r.type("Phigros2.Utils.MultiLanguageText","MultiLanguageTextString"));r.call(title,".ctor");r.call(title,"set_NewString",{"System.String"},{r.managedString(text)});return title;}
P emptyListeners(Runtime&r,P method,int param){P arrayType=r.type_get_object(r.method_get_param(method,param));P element=r.call(arrayType,"GetElementType");int zero=0;return r.stat(r.type("System","Array"),"CreateInstance",{"System.Type","System.Int32"},{element,&zero});}
void makeNativeSettings(Runtime&r,P setting){
 clearNativeSettings(r);P source=r.get<P>(setting,"scrollRect"),original=r.get<P>(setting,"settingItemsManager");
 if(!r.alive(source)||!r.alive(original))throw std::runtime_error("Native setting templates unavailable");
 P sourceGo=go(r,source),parent=r.call(transform(r,source),"get_parent");P root=clone(r,sourceGo,parent,nativeSettingsRoot);active(r,root,false);
 // The original tab/page is hidden while MOD is open; the clone must not
 // remain beneath that same hidden ancestor.
 bool keepWorld=true;r.call(transform(r,root),"SetParent",{"UnityEngine.Transform","System.Boolean"},{transform(r,setting),&keepWorld});
 try{
  P scroll=r.component(root,r.type("UnityEngine.UI","ScrollRect")),content=r.call(scroll,"get_content"),viewport=r.call(scroll,"get_viewport");
  for(int i=r.unbox<int>(r.call(content,"get_childCount"))-1;i>=0;--i){P child=r.call(content,"GetChild",{"System.Int32"},{&i});bool world=false;r.call(child,"SetParent",{"UnityEngine.Transform","System.Boolean"},{nullptr,&world});r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go(r,child)});}
  nativeSettingsManager=r.call(root,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.klass("SettingItemsManager")))});
  r.put(nativeSettingsManager,"viewport",viewport);r.put(nativeSettingsManager,"content",content);r.put(nativeSettingsManager,"itemsHolder",content);r.put(nativeSettingsManager,"offset",0.f);
  for(const char*field:{"buttonPrefab","sliderPrefab","togglePrefab"})r.put(nativeSettingsManager,field,r.get<P>(original,field));
  P addButton=r.resolve(r.klass("SettingItemsManager"),"AddButton",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","UnityEngine.Events.UnityAction[]"});
  NSArray*titles=@[@"\u8c31\u5e93\u7ba1\u7406",@"\u7ae0\u8282\u7ba1\u7406",@"\u76ae\u80a4 / \u97f3\u6548 / \u7279\u6548",@"\u9ad8\u7ea7\u53c2\u6570\uff08\u5224\u5b9a / HP / \u7ec3\u4e60\uff09"];
  for(int action=0;action<(int)titles.count;++action){P listeners=emptyListeners(r,addButton,1);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(addButton,nativeSettingsManager,{nativeTitle(r,titles[action]),listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);P button=r.get<P>(item,"button");emptyClick(r,button);nativeActions[button]=action;}
  P toggle=r.resolve(r.klass("SettingItemsManager"),"AddToggle",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Boolean","UnityEngine.Events.UnityAction<System.Boolean>[]"});
  for(NSArray*entry in @[@[@"autoplay",@"AutoPlay"],@[@"noise",@"\u566a\u57df"],@[@"clearOriginalNoise",@"\u6e05\u9664\u539f\u8c31\u566a\u57df"],@[@"hpEnabled",@"HP \u751f\u5b58"],@[@"fullScreen",@"\u5168\u5c4f\u5224\u5b9a"],@[@"accuracy",@"\u5b9e\u65f6 ACC"],@[@"noCombo",@"\u53bb\u9664\u8fde\u51fb\u5206"],@[@"practiceMode",@"\u533a\u95f4\u7ec3\u4e60"],@[@"showShortcuts",@"\u9009\u66f2\u5feb\u6377\u6309\u94ae"]]){
   bool value=PMSettingBool([entry[0]UTF8String]);P listeners=emptyListeners(r,toggle,2);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(toggle,nativeSettingsManager,{nativeTitle(r,entry[1]),&value,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,entry[0],value?1.f:0.f,false});
  }
  P slider=r.resolve(r.klass("SettingItemsManager"),"AddSlider",{"Phigros2.Utils.MultiLanguageText.MultiLanguageTextString","System.Single","System.Single","System.Single","UnityEngine.Events.UnityAction<System.Single>[]"});
  float value=[[[PMSettings shared]value:@"opacity"]floatValue],low=0,high=1;P listeners=emptyListeners(r,slider,4);uint32_t h=r.gchandle_new(listeners,false);P item=nullptr;try{item=r.invokeOn(slider,nativeSettingsManager,{nativeTitle(r,@"\u60ac\u6d6e\u7a97\u900f\u660e\u5ea6"),&value,&low,&high,listeners});}catch(...){r.gchandle_free(h);throw;}r.gchandle_free(h);nativeOptions.push_back({item,@"opacity",value,true});
  r.call(nativeSettingsManager,"RefreshItems");r.call(nativeSettingsManager,"RefreshPosition");active(r,root,true);
 }catch(...){clearNativeSettings(r);throw;}
}
void pollNativeSettings(Runtime&r){
 P root=target(r,nativeSettingsRoot);if(!r.alive(root))return;
 PMModEditor*editor=[PMModEditor shared];if(nativeAdvanced&&editor.hidden){nativeAdvanced=false;active(r,root,true);for(auto&option:nativeOptions){float value=[[[PMSettings shared]value:option.key]floatValue];if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&value});else{bool on=value!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}option.last=value;}}
 if(nativeAdvanced)return;
 for(auto&option:nativeOptions){float value=option.slider?r.unbox<float>(r.call(option.item,"get_Value")):(r.unbox<bool>(r.call(option.item,"get_Value"))?1.f:0.f);if(std::fabs(value-option.last)<.0001f)continue;NSString*error=nil;if([[PMSettings shared]setValue:@(value) forKey:option.key error:&error])option.last=value;else{float old=option.last;if(option.slider)r.call(option.item,"set_Value",{"System.Single"},{&old});else{bool on=old!=0;r.call(option.item,"set_Value",{"System.Boolean"},{&on});}PMDiagnosticsWrite(error.UTF8String);}}
}
bool pressNativeSetting(Runtime&r,P button){auto found=nativeActions.find(button);if(found==nativeActions.end())return false;UIWindow*w=window();UIView*source=w.rootViewController.view;
 if(found->second==0)PMShowContent(source,NO);else if(found->second==1)PMShowContent(source,YES);else if(found->second==2)PMShowResourcePackPicker(source);else{nativeAdvanced=true;active(r,target(r,nativeSettingsRoot),false);[[PMModEditor shared]begin];[PMModEditor shared].hidden=NO;}
 return true;
}
}
