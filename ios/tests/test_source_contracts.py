"""Source/protocol consistency guards; these are NOT an Apple SDK build."""
import json,re,unittest,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContracts(unittest.TestCase):
 def test_manifest_cpp_protocol_is_not_stale(self):
  manifest=json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  protocol=(ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8')
  header=(ROOT/'PhiMod/Core/PMHookManifest.hpp').read_text(encoding='utf-8')
  generated=re.findall(r'\{(0x[0-9a-f]+)u,(0x[0-9a-f]+)u\}',header)
  self.assertEqual(len(manifest),55);self.assertEqual(len(generated),55)
  for i,(entry,(site,word)) in enumerate(zip(manifest,generated)):
   self.assertRegex(protocol,r'\b'+re.escape(entry['id'])+'='+str(i)+r',')
   self.assertEqual(int(site,16),entry['rva'])
   self.assertEqual(int(word,16),int.from_bytes(bytes.fromhex(entry['bytes']),'little'))
 def test_no_declared_but_missing_ui_implementation(self):
  header=(ROOT/'PhiMod/Sources/PMSceneUI.hpp').read_text(encoding='utf-8')
  impl=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  for name in re.findall(r'\b(?:void|bool)\s+(\w+)\(',header):self.assertRegex(impl,r'\b'+name+r'\(')
  self.assertIn('emptyClick(r,s.button)',impl)
  self.assertIn('"mirrorBackground"',impl)
  self.assertIn('"tabAnimators"',impl)
  self.assertIn('saveRequested',impl)
  self.assertIn('validateSnapshot:self.draft',impl)
 def test_ui_creation_rolls_back_instead_of_retrying_every_frame(self):
  s=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  selector=s[s.index('void makeSelector('):s.index('void selectorLayout(')]
  self.assertIn('selectorRoot=r.gchandle_new(self,false);\n  throw;',selector)
  settings=s[s.index('void settingsFrame('):s.index('bool press(')]
  self.assertIn('visible=visible&&layoutReady;',s)
  self.assertIn('if(tabFailed)return;',settings)
  self.assertIn('tabFailed=true;tabButton=tabText=nullptr;dispose(r,tabRoot,true);throw;',settings)
  self.assertLess(settings.index('emptyClick(r,button)'),settings.index('tabButton=button;tabText=text;'))
  self.assertLess(settings.index('validateSnapshot:d'),settings.index('[PMRuntime applyJudgeSettings:'))
 def test_scene_state_avoids_posix_open_name_collision(self):
  s=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertNotRegex(s,r'\bopen\b')
  self.assertIn('modEditorOpen=false',s)
  self.assertIn('modEditorOpen=true',s)
  self.assertIn('if(!modEditorOpen)return;',s)
 def test_ci_shell_scripts_use_lf(self):
  for relative in ('build_unsigned.sh', 'tests/run_core_tests.sh'):
   self.assertNotIn(b'\r', (ROOT/relative).read_bytes(), relative)
 def test_judge_cannot_enable_without_protection(self):
  s=(ROOT/'PhiMod/Sources/PMRuntime.mm').read_text(encoding='utf-8')
  self.assertLess(s.index('[PMHookBackend protectJudgeChange]'),s.index('controller.apply(*patch'))
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('Gateway manifest mismatch',hook)
  self.assertIn('Entry gate instruction mismatch',hook)
  self.assertIn('__atomic_store_n',hook)
  result=hook[hook.index('P onResultStart('):hook.index('bool onResultMove(')]
  self.assertIn('if(!guard.load())return orig<P(*)(P,P)>(h::resultStart)(self,mi);',result)
  self.assertNotIn('renderPracticeResult(self);',result)
  self.assertIn('return orig<P(*)(P,P)>(h::resultStart)(self,mi);',result)
  self.assertNotIn('return nullptr;',result)
  move=hook[hook.index('bool onResultMove('):hook.index('void onLifeStart(')]
  self.assertIn('if(!guard.load())return orig<JudgeFn>(h::resultMove)(iterator,mi);',move)
  self.assertIn('bool more=orig<JudgeFn>(h::resultMove)(iterator,mi);',move)
  self.assertIn('return more;',move)
  self.assertIn('resultPresented=true;inResult=false;',move)
  self.assertNotIn('return false;',move)
  self.assertNotIn('r.get<P>(iterator,"<>4__this")',move)
  self.assertNotIn('r.put(iterator,"<>1__state",-1)',move)
  self.assertEqual(move.count('orig<JudgeFn>(h::resultMove)(iterator,mi)'),2)
  self.assertIn('resultPresented=false',hook)
  self.assertIn('for(auto c:attempt->flushPendingHolds())',result)
  self.assertIn('!levelOverStarted&&pmhp::failureReady(r,progressControl)',hook)
  self.assertIn('levelOverStarted=true',hook)
  self.assertIn('void clearGameplayMask(Runtime&r,P progressControl)',hook)
  self.assertIn('clearGameplayMask(r,progressControl)',hook)
  self.assertIn('orig<VoidFn>(h::judgeUpdate)(self,mi)',hook)
  self.assertIn('tickGameplay(r,progressControl,"JudgeControl.Update")',hook)
  self.assertIn('diagnosticTick(r,progressControl,source)',hook)
  progress_update=hook[hook.index('void onProgressUpdate('):hook.index('void onJudgeUpdate(')]
  self.assertIn('orig<VoidFn>(h::progressUpdate)(self,mi)',progress_update)
  self.assertNotIn('tickGameplay(',progress_update)
  self.assertIn('loadingMaskCleared=false',hook)
  self.assertIn('registerOne(note)',hook)
  self.assertNotIn('registerChart(',hook)
  level_over=hook[hook.index('P onProgressLevelOver('):hook.index('void onLevelCodes(')]
  self.assertIn('return orig<P(*)(P,P)>(h::progressLevelOver)(self,mi);',level_over)
  self.assertIn('pmhp::finish(R())',level_over)
  self.assertIn('if(!options.assisted())',hook)
  self.assertIn('if(!guard.load())',hook)
  self.assertIn('requiresSaveProtection()',hook)
  self.assertIn('bool readAccuracy(P self,float &outScore,int &outTotal)',hook)
  self.assertIn('orig<VoidFn>(h::scoreUpdate)(self,mi);',hook)
  score=hook[hook.index('void onScoreUpdate('):hook.index('P onResultInfo(')]
  self.assertLess(score.index('orig<VoidFn>(h::scoreUpdate)(self,mi);'),score.index('readAccuracy(self,value,total)'))
  self.assertIn('scoreOfNote',score);self.assertIn('_percent',score)
  self.assertNotIn('fault(e)',score)
  self.assertIn('orig<VoidFn>(h::lifeStart)(self,mi);',hook)
  self.assertIn('orig<VoidFn>(h::lifeModStart)(self,mi);',hook)
  self.assertIn('orig<VoidFn>(h::lifeUpdate)(self,mi);',hook)
 def test_modes_ready_only_after_real_pipeline_validation(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('@"noiseReady":@(ready&&!broken)',hook);self.assertIn('@"unifiedReady":@(ready&&!broken)',hook)
  self.assertLess(hook.index('pmmodes::validate(r)'),hook.index('__atomic_store_n'))
  modes=(ROOT/'PhiMod/Sources/PMChartModes.mm').read_text(encoding='utf-8')
  for value in ('unifiedNote(', 'FromJsonOverwrite', 'holes.masks(', 'UpdateBlocksTransform', 'holes.allows(', 'holdGrace.inject(', 'fxClock.pulse('):self.assertIn(value,modes)
  # Keep mutations on the original Chart so Unity's native lifecycle computes
  # floorPosition/realTime on the same object SetInformation later consumes.
  self.assertNotIn('"FromJson"',modes);self.assertNotIn('chartRoot',modes)
  self.assertIn('originalRoot',modes);self.assertIn('originalBlocksRoot',modes)
  self.assertIn('geometryRevision()',modes)
  self.assertIn('if(options.clearNoise&&!options.noise)',modes)
  self.assertIn('handled=true;if(out)*out=nullptr;return false;',modes)
  self.assertNotIn('ClearRenderTexture',modes)
  clear=modes[modes.index('void afterInformation('):modes.index('void beginFrame(')]
  self.assertIn('overwrite(r,chart,"{\\"blockAreaList\\":[]}")',clear)
  self.assertIn('Original noise removal incomplete',clear)
  self.assertLess(clear.index('overwrite(r,chart'),clear.index('if(!options.noise)return;'))
  ui=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertNotIn('if(i==1||i==2)return true',ui)
  self.assertIn('i==2?@((old+1)%5)',ui)
  self.assertNotIn('self.draft[@"noise"]=@NO',ui)
 def test_configuration_no_longer_rejects_ported_modes(self):
  s=(ROOT/'PhiMod/Sources/PMGameplay.mm').read_text(encoding='utf-8')
  self.assertNotIn('pipelines not implemented',s)
  self.assertIn('[backend[@"ok"] boolValue]',s)
  self.assertIn('[backend[@"noiseReady"] boolValue]',s)
  self.assertIn('[backend[@"unifiedReady"] boolValue]',s)
  self.assertIn('preview does not apply',s)
  ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  self.assertNotIn('选曲快捷按钮（待接入）',ui)
  self.assertNotIn('隐藏 Combo',ui)
  self.assertIn('Accuracy（去除连击分）',ui)
 def test_hold_fx_runs_before_native_move(self):
  s=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  f=s[s.index('void onHoldMove('):s.index('template<h::Index i>void onNoteMove(')]
  self.assertLess(f.index('pmmodes::holdMove('),f.index('orig<VoidFn>'))
  self.assertLess(f.index('orig<VoidFn>'),f.index('pmmodes::moved('))
 def test_autoplay_miss_only_defers_real_holds(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('bool hold=attempt->noteType(code)==3;',hook)
  self.assertIn('onPerfect(self,code,0,{0,0,0},hold,nullptr)',hook)
 def test_preview_types_use_their_real_namespaces(self):
  s=(ROOT/'PhiMod/Sources/PMChartModes.mm').read_text(encoding='utf-8')
  self.assertNotIn('r.klass("PreviewBlockControl")',s)
  self.assertNotIn('r.klass("PreviewElementUpdateControl")',s)
  self.assertIn('r.type("ProjectEditor.PreviewScripts","PreviewBlockControl")',s)
  self.assertIn('r.type("Phigros2.Level.Scripts","PreviewElementUpdateControl")',s)
  self.assertIn('System.Collections.Generic.List<ProjectEditor.PreviewScripts.PreviewBlockControl>',s)
 def test_actual_click_paths_and_original_button_passthrough(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('h::buttonClick)(self,event,mi)',hook)
  self.assertIn('h::buttonSubmit)(self,event,mi)',hook)
  self.assertIn('if(!pmscene::ownsButton(self))return false',hook)
  self.assertIn('if(button==0)dispatchModButton(self)',hook)
  ui=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertIn('set_blocksRaycasts',ui);self.assertIn('set_interactable',ui)
 def test_native_hp_and_pending_failure_transition(self):
  hp=(ROOT/'PhiMod/Sources/PMHPLife.mm').read_text(encoding='utf-8')
  for value in ('LevelMod/SecretChallengeLifeMod','LevelMod/HPDisplay','ConfigureCanvas','ApplyShaderParameters','SmoothDamp','originalModsRoot','AudioFadeOut','failure.ready(time(r))'):self.assertIn(value,hp)
  self.assertNotIn('r.call(self,"Start")',hp)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('pmhp::barUpdate(R(),self)',hook)
  self.assertIn('bool hpLost=attempt->options().hpEnabled&&attempt->trackLost();',hook)
  self.assertIn('pendingAction(playing||pmhp::failing()||hpLost',hook)
  self.assertIn('attempt->acknowledgeAction(action)',hook)
  self.assertNotIn('lastTickFrame',hook)
  self.assertIn('bool inChallenge=r.get<bool>(progressControl,"_inChallengeMode")',hook)
  self.assertIn('pmhp::finishChallenge(r,progressControl)',hook)
  self.assertIn('if(options.hpEnabled)pmhp::beginAttempt(attempt->hp())',hook)
 def test_hold_array_edit_is_scoped_and_no_android_layout(self):
  bridge=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  modes=(ROOT/'PhiMod/Sources/PMChartModes.mm').read_text(encoding='utf-8')
  self.assertIn('PM_API(value_box)',bridge);self.assertIn('"SetValue",{"System.Object","System.Int32"}',bridge)
  self.assertIn('HoldScope::~HoldScope()',modes);self.assertIn('numOfFingers",count_',modes)
  self.assertNotIn('sizeof(P)*4',modes)
  # Collect only controllers moved by the original scheduler, not all future
  # notes via managed list reflection every frame (important on iPad6).
  frame=modes[modes.index('void frame('):modes.index('void late(')]
  self.assertNotIn('clickControls',frame)
 def test_callbacks_and_build_marker_match_manifest(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  manifest=json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  values=hook[hook.index('P callbacks[h::Count]'):hook.index('auto slots=',hook.index('P callbacks[h::Count]'))]
  self.assertEqual(values.count('reinterpret_cast<P>'),len(manifest))
  self.assertIn('PMGameplay-contract-v2-'+str(len(manifest)),hook)
  package=(ROOT/'tools/package_unsigned_ipa.py').read_text(encoding='utf-8')
  self.assertIn('PMGameplay-contract-v2-'+str(len(manifest)),package)
 def test_hp_diagnostics_are_persistent_and_copyable(self):
  diagnostics=(ROOT/'PhiMod/Sources/PMDiagnostics.mm').read_text(encoding='utf-8')
  ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  hp=(ROOT/'PhiMod/Sources/PMHPLife.mm').read_text(encoding='utf-8')
  self.assertIn('PhiMod-diagnostics.log',diagnostics)
  self.assertIn('PMDiagnosticsBeginSession',diagnostics)
  self.assertIn('PMDiagnosticsBeginSession();',ui)
  self.assertIn('writeToFile:path atomically:YES',diagnostics)
  self.assertIn('UIPasteboard.generalPasteboard.string=PMDiagnosticsTail(400)',ui)
  self.assertIn('judgeUpdateHook',hook)
  self.assertIn('HP failureReady: begin freeze/fade',hp)
  self.assertIn('HP attempt initialized life=',hp)
  self.assertIn('ChallengeModeOver',hp)
 def test_packager_rejects_old_framework_before_copying_payload(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);(root/'source/Payload').mkdir(parents=True);(root/'PhiMod.framework').mkdir()
   for marker in (b'PMGameplay-v1',b'PMGameplay-v2',b'PMGameplay-v2\0PMGameplay-contract-v2-45'):
    (root/'PhiMod.framework/PhiMod').write_bytes(marker)
    result=subprocess.run([sys.executable,str(ROOT/'tools/package_unsigned_ipa.py'),'--source',str(root/'source'),'--framework',str(root/'PhiMod.framework'),'--output',str(root/'out.ipa')],capture_output=True,text=True,encoding="utf-8",errors="replace")
    self.assertNotEqual(result.returncode,0);self.assertIn('Stale framework',result.stderr);self.assertFalse((root/'out.ipa').exists())
 def test_bridge_checks_value_type_and_size(self):
  s=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  self.assertIn('class_value_size(c,&alignment)!=sizeof(T)',s)
  self.assertIn('checkClass<T>(class_from_type(field_get_type(f)))',s)
  self.assertIn('checkClass<T>(object_get_class(obj))',s)
if __name__=='__main__':unittest.main()
