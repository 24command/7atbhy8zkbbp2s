"""Source/protocol consistency guards; these are NOT an Apple SDK build."""
import json,re,unittest,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContracts(unittest.TestCase):
 def test_free_challenge_native_transitions(self):
  selection=(ROOT/'PhiMod/Sources/PMChallengeSelection.inc').read_text('utf8')
  launch=selection.split('static void launch(',1)[1].split('static void press(',1)[0]
  self.assertIn('r.call(control,"Play")',launch)
  self.assertIn('withQueue(r,control,slots.get()',launch)
  self.assertIn('pmchallenge::startVariable(r,list)',launch)
  self.assertNotIn('TurnToNextScene',launch)
  result=(ROOT/'PhiMod/Sources/PMChallengeResults.hpp').read_text('utf8')
  self.assertIn('bool keepRank = false;',result)
  self.assertIn('r.call(self,"Back",{"System.Boolean"},{&keepRank})',result)
  self.assertNotIn('TurnToNextScene',result)
 def test_manifest_cpp_protocol_is_not_stale(self):
  manifest=json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  protocol=(ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8')
  header=(ROOT/'PhiMod/Core/PMHookManifest.hpp').read_text(encoding='utf-8')
  generated=re.findall(r'\{(0x[0-9a-f]+)u,(0x[0-9a-f]+)u\}',header)
  self.assertEqual(len(manifest),74);self.assertEqual(len(generated),74)
  for i,(entry,(site,word)) in enumerate(zip(manifest,generated)):
   self.assertRegex(protocol,r'\b'+re.escape(entry['id'])+'='+str(i)+r',')
   self.assertEqual(int(site,16),entry['rva'])
   self.assertEqual(int(word,16),int.from_bytes(bytes.fromhex(entry['bytes']),'little'))
 def test_extra_json_extension_tracks_and_resource_copy_are_wired(self):
  converter=(ROOT/'PhiMod/Sources/PMExtensionTracks.mm').read_text(encoding='utf-8')
  store=(ROOT/'PhiMod/Sources/PMContentStore.mm').read_text(encoding='utf-8')
  runtime=(ROOT/'PhiMod/Sources/PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  android=""  # Android reference is local-only; CI checks the ported source.
  for tag in ('"F "','"R "','"A "','"K "','"V "'):self.assertIn(tag,converter)
  for name in ('effects-version.txt','extra.json','targetRange','bezierPoints','easingLeft','easingRight'):self.assertIn(name,android+converter)
  self.assertIn('preserveExtraResources(folder,e)',store)
  self.assertIn('for(int i=0;i<33;i++)',runtime)
  self.assertNotIn('rpeVideo', (ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8'))
  self.assertNotIn('rpeShader', (ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8'))
 def test_mainline_full_unlock_is_settings_driven_and_guarded_to_official_chapters(self):
  protocol=(ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8')
  hooks=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  unlock=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  content=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('mainlineCheckUnlock=64',protocol);self.assertIn('mainlineApplyMapCover=67',protocol)
  for name in ('CheckSongUnlock','Chapter9Phase1Control.Start','Chapter9Phase1Control.ToPhase2','Chapter9Phase2Control.ApplyMapCover'):
   self.assertIn(name,(ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  self.assertIn('pmcontent::isMainlineSong(identifier)',hooks)
  self.assertIn('isMainlineChapter(NSString*code)',content)
  self.assertIn('refreshMainlineAccess',content+unlock)
  self.assertIn('"mainlineUnlock"', (ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8'))
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
  self.assertIn('if(!guard.load())return more;',move)
  self.assertIn('bool more=orig<JudgeFn>(h::resultMove)(iterator,mi);',move)
  self.assertIn('return more;',move)
  self.assertIn('resultPresented=true;inResult=false;',move)
  self.assertNotIn('return false;',move)
  self.assertNotIn('r.get<P>(iterator,"<>4__this")',move)
  self.assertNotIn('r.put(iterator,"<>1__state",-1)',move)
  self.assertEqual(move.count('orig<JudgeFn>(h::resultMove)(iterator,mi)'),1)
  self.assertLess(move.index('bool more=orig<JudgeFn>'),move.index('difficultyResultLabel'))
  self.assertLess(move.index('if(!guard.load())return more;'),move.index('resultPresented=true'))
  self.assertIn('resultPresented=false',hook)
  self.assertIn('for(auto c:attempt->flushPendingHolds())',result)
  self.assertIn('!levelOverStarted&&pmhp::failureReady(r,progressControl)',hook)
  self.assertIn('levelOverStarted=true',hook)
  self.assertIn('void clearGameplayMask(Runtime&r,P progressControl)',hook)
  self.assertIn('clearGameplayMask(r,progressControl)',hook)
  self.assertIn('pmcontent::judgeWithHudPause(r,self,mi,orig<VoidFn>(h::judgeUpdate))',hook)
  content=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  wrapper=content[content.index('void judgeWithHudPause('):content.index('\n}',content.index('void judgeWithHudPause('))+2]
  self.assertEqual(wrapper.count('original(judge,mi);'),1)
  self.assertNotIn('r.put(',wrapper)
  self.assertNotIn('InverseTransformPoint',wrapper)
  self.assertIn('tickGameplay(r,progressControl,"JudgeControl.Update")',hook)
  judge_update=hook[hook.index('void onJudgeUpdate('):hook.index('void onAddressableAudioUpdate(')]
  self.assertLess(judge_update.index('ensureFloorArray('),judge_update.index('orig<VoidFn>(h::judgeUpdate)'))
  self.assertIn('LevelInformation.floorPositions expanded',hook)
  self.assertIn('floors=%d/%lu',hook)
  self.assertIn('diagnosticTick(r,progressControl,source)',hook)
  progress_update=hook[hook.index('void onProgressUpdate('):hook.index('void onJudgeUpdate(')]
  self.assertIn('orig<VoidFn>(h::progressUpdate)(self,mi)',progress_update)
  self.assertRegex(progress_update,r'if\(attempt && attempt->trackLost\(\) && !levelOverStarted && self==progress\(\)\)\s*tickGameplay')
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
  self.assertLess(score.index('orig<VoidFn>(h::scoreUpdate)(self,mi);'),score.index('readAccuracy(self,accuracy,total)'))
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
  self.assertIn('addSetting:@"accuracy"',ui)
  self.assertIn('addSetting:@"noCombo"',ui)
  scene=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertIn('key:@"accuracy"',scene);self.assertIn('key:@"noCombo"',scene)
  core=(ROOT/'PhiMod/Core/PMGameplayCore.hpp').read_text(encoding='utf-8')
  self.assertIn('accuracyDisplay',core);self.assertIn('noComboScore',core)
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
  for value in ('LevelMod/SecretChallengeLifeMod','LevelMod/HPDisplay','ConfigureCanvas','ApplyShaderParameters','SmoothDamp','InstantiateAsync','ReleaseInstance','AudioFadeOut','get_unscaledTime'):self.assertIn(value,hp)
  self.assertNotIn('r.call(self,"Start")',hp)
  prepare=hp[hp.index("void prepare("):hp.index("P valueCall(")]
  self.assertNotIn('r.put(info,"levelMods"',hp)
  self.assertNotIn("InstantiateAsync",prepare)
  loads=hp[hp.index("void loadVisuals("):hp.index("std::string loadingStatus(")]
  self.assertLess(loads.index('"chartLoaded"'),loads.index('"InstantiateAsync"'))
  self.assertIn('r.object_unbox(boxed)',hp)
  self.assertIn('pmhp::loadVisuals(R(),self)', (ROOT/"PhiMod/Sources/PMHookBackend.mm").read_text(encoding="utf-8"))
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('pmhp::barUpdate(R(),self)',hook)
  self.assertIn('bool hpLost=attempt->options().hpEnabled&&attempt->trackLost();',hook)
  self.assertIn('pendingAction(playing||pmhp::failing()||hpLost',hook)
  self.assertIn('attempt->acknowledgeAction(action)',hook)
  self.assertNotIn('lastTickFrame',hook)
  self.assertIn('HP failure ready; returning to SongSelector',hook)
  self.assertIn('pmhp::finish(r)',hook)
  self.assertIn('attempt->seedTrackHP(pmchallenge::beginTrack(r,p,options.hpMax));pmhp::beginAttempt(attempt->hp())',hook)
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
  self.assertIn('PMGameplay-contract-v2-'+str(len(manifest))+'-ios404',hook)
  package=(ROOT/'tools/package_unsigned_ipa.py').read_text(encoding='utf-8')
  self.assertIn('PMGameplay-contract-v2-'+str(len(manifest))+'-ios404',package)
 def test_practice_rate_segment_hooks_and_android_style_mode_categories(self):
  practice=(ROOT/'PhiMod/Sources/PMPractice.mm').read_text(encoding='utf-8')
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  settings=(ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8')
  self.assertIn('PMGameplay-contract-v2-74-ios404',hook)
  self.assertIn('audioUpdate=55', (ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8'))
  self.assertIn('lineCreateNote=56', (ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8'))
  self.assertIn('AddressableAudioSource.Update', (ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  self.assertIn('onAddressableAudioUpdate',hook)
  self.assertIn('judgeRateEnter',practice);self.assertIn('set_pitch',practice);self.assertIn('segmentPaused',practice)
  self.assertIn('countdownActive',practice);self.assertIn('clearControllers',practice);self.assertIn('restartSegment',hook);self.assertIn('requestedPosition',practice)
  self.assertIn('practiceCountdown',settings)
  self.assertLess(hook.index('orig<VoidFn>(h::audioUpdate)(self,mi)'),hook.index('pmpractice::audioAfter(R(),self)'))
  progress=hook[hook.index('void onProgressUpdate('):hook.index('void onJudgeUpdate(')]
  self.assertLess(progress.index('pmpractice::beforeProgress'),progress.index('orig<VoidFn>(h::progressUpdate)'))
  self.assertIn('pmpractice::afterProgress(R(),self)',progress)
  self.assertIn('Practice three-second count-in started',practice)
  for key in ('practiceMode','practiceLoop','practiceCountdown','practiceStart','practiceEnd','practicePosition','playbackRate'):self.assertIn('"'+key+'"',settings)
  for category in ('模式','练习','噪域','HP'):self.assertIn('@"'+category+'"',ui)
  self.assertIn('practiceCommand:',ui);self.assertIn('practiceCommand:(NSInteger)action',hook)
 def test_practice_preview_rewinds_chart_and_preserves_crossing_holds(self):
  preview=(ROOT/'PhiMod/Sources/PMPracticePreview.mm').read_text(encoding='utf-8')
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('n.time+n.duration>current',preview)
  self.assertIn('r.put(n.note,"realTime",n.time)',preview)
  self.assertIn('r.put(n.note,"holdTime",n.duration)',preview)
  self.assertIn('r.put(n.note,"floorPosition",n.floor)',preview)
  self.assertIn('std::lower_bound',preview)
  self.assertIn('pmpractice::allowNoteCreation()',hook)
  manager=hook[hook.index('void onNoteManager('):hook.index('bool onBlocking(')]
  self.assertLess(manager.index('pmpractice::previewFrame('),manager.index('orig<VoidFn>(h::noteManager)'))
  controls=(ROOT/'PhiMod/Sources/PMPracticeControls.mm').read_text(encoding='utf-8')
  for value in ('scrubEnd','markStart','markEnd','rateChanged','practiceCommand:','practiceStatus','NSRunLoopCommonModes'):self.assertIn(value,controls)
  native=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertIn('categoryChanged:',native);self.assertIn('practiceMode',native)
  self.assertIn('self.category=sender.selectedSegmentIndex',native)
 def test_update_heartbeats_are_independent_and_log_original_return(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('heartbeatDue(lastProgressHeartbeat,count)',hook)
  self.assertIn('heartbeatDue(lastJudgeHeartbeat,count)',hook)
  self.assertIn('ProgressControl.Update original returned',hook)
  self.assertIn('JudgeControl.Update original returned',hook)
  for name in ('clipTime=','prepared=','chart=','HP loader %s'):self.assertIn(name,hook)
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
   for marker in (b'PMJudgeHook-v1\0PMGameplay-v2\0PMGameplay-contract-v2-68\0',b'PMGameplay-v1',b'PMGameplay-v2',b'PMGameplay-v2\0PMGameplay-contract-v2-74-ios404'):
    (root/'PhiMod.framework/PhiMod').write_bytes(marker)
    result=subprocess.run([sys.executable,str(ROOT/'tools/package_unsigned_ipa.py'),'--source',str(root/'source'),'--framework',str(root/'PhiMod.framework'),'--output',str(root/'out.ipa')],capture_output=True,text=True,encoding="utf-8",errors="replace")
    self.assertNotEqual(result.returncode,0);self.assertIn('Stale framework',result.stderr);self.assertFalse((root/'out.ipa').exists())
 def test_hp_damage_does_not_invoke_unity_inside_judgement_callback(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  hp=(ROOT/'PhiMod/Sources/PMHPLife.mm').read_text(encoding='utf-8')
  observe=hook[hook.index('void observe('):hook.index('void onPerfect(')]
  self.assertNotIn('pmhp::frame(',observe);self.assertNotIn('pmhp::flash(',observe)
  self.assertNotIn('"FlashLifeText"',hp)
  score=hook[hook.index('void onScoreUpdate('):hook.index('P onResultInfo(')]
  self.assertIn('pmhp::frame(r,attempt->hp())',score)
  self.assertIn('HP Miss original returned',hook)
 def test_content_bridge_is_connected_and_safe_archive_paths_are_checked(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  for name in ('assetConstructor','assetRelease','levelInfo','beforeChart','afterChart','noteMoved','visuals','levelEnd','attach'):self.assertIn('pmcontent::'+name,hook)
  archive=(ROOT/'PhiMod/Sources/PMArchive.mm').read_text(encoding='utf-8')
  self.assertIn('if(!ok)break;',archive)
  self.assertIn('path.lowercaseString.UTF8String',archive)
  store=(ROOT/'PhiMod/Sources/PMContentStore.mm').read_text(encoding='utf-8')
  for name in ('library.backup.json','startAccessingSecurityScopedResource','PMExtractArchiveURL','phigros-phi-chapter','chart-native.json','source.rpe.json'):self.assertIn(name,store)
  self.assertIn('NSFileCoordinator',archive)
  self.assertIn('error:&coordinationError',archive)
  ui=(ROOT/'PhiMod/Sources/PMContentUI.mm').read_text(encoding='utf-8')
  self.assertIn('initForOpeningContentTypes:',ui);self.assertIn('initForExportingURLs:',ui)
  self.assertIn('contentCommand:',ui)
 def test_practice_canvas_matches_android_transport_structure(self):
  source=(ROOT/'PhiMod/Sources/PMPracticeControls.mm').read_text(encoding='utf-8')
  for value in ('PHI / PRACTICE','切换 UI','3s 倒计时','0xff42afff','0xffee5164','0xff37d35b','self.dragging','self.whiteUi','queuePreview','流速'):self.assertIn(value,source)
  self.assertNotIn('NSLayoutConstraint',source)
 def test_content_build_includes_vendors_frameworks_and_host_tests(self):
  build=(ROOT/'build_unsigned.sh').read_text(encoding='utf-8')
  for name in ('PMZipVendor.cpp','PMVorbisVendor.cpp','AVFoundation','UniformTypeIdentifiers'):self.assertIn(name,build)
  workflow=next(p for p in (ROOT.parent/'.github/workflows/build-ios.yml',ROOT/'.github/workflows/build-ios.yml') if p.is_file()).read_text(encoding='utf-8')
  self.assertIn('run_content_tests.sh',workflow)
 def test_content_audio_uses_retained_ios_overload_and_readback(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertNotIn('"Copy",{"System.IntPtr","System.Single[]"',source)
  self.assertIn('"copy_from_unmanaged"',source)
  self.assertIn('{"System.IntPtr","System.Int32","System.Array","System.Int32"},{&ptr,&zero,data,&count}',source)
  self.assertIn('validatePcmCopy(r);',source)
  self.assertIn('r.unbox<float>(r.arrayAt(data,i))!=samples[i]',source)
  self.assertIn('catch(...){r.gchandle_free(chunkRoot);throw;}',source)
  self.assertIn('"SetData",{"System.Single[]","System.Int32"}',source)
 def test_android_style_navigation_and_practice_entries(self):
  source=(ROOT/'PhiMod/Sources/PMOfficialUI.mm').read_text(encoding='utf-8')
  for item in ('@"谱库",@"章节",@"判定",@"模式",@"设置"','.267949','52.0/96','UIAccessibilityIsReduceMotionEnabled','accessibilityActivate'):
   self.assertIn(item,source)
  editor=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  for item in ('PMOfficialCategories','modeCard:','PMOfficialToggle','chooseMode:','practiceWhiteUi','practicePosition','copyDiagnostics','self.category=3'):
   self.assertIn(item,editor)
  content=(ROOT/'PhiMod/Sources/PMContentUI.mm').read_text(encoding='utf-8')
  self.assertIn('PMContentCell',content)
  self.assertIn('UIDocumentPickerViewController',content)
 def test_diagnostics_calls_are_declared(self):
  header=(ROOT/'PhiMod/Sources/PMDiagnostics.h').read_text(encoding='utf-8')
  declarations=set(re.findall(r'\b(PMDiagnostics\w+)\s*\(',header))
  for path in (ROOT/'PhiMod/Sources').glob('*.mm'):
   if path.name=='PMDiagnostics.mm':continue  # Private implementation helpers.
   calls=set(re.findall(r'\b(PMDiagnostics\w+)\s*\(',path.read_text(encoding='utf-8')))
   self.assertFalse(calls-declarations,f'{path.name}: undeclared diagnostics calls {calls-declarations}')
 def test_literal_overload_audit_rejects_stripped_method(self):
  sys.path.insert(0,str(ROOT/'tools'))
  from verify_gameplay_contracts import verify_sources
  dump = '''// Namespace: System
public struct IntPtr // TypeDefIndex: 1
{
}
// Namespace: System
public abstract class Array // TypeDefIndex: 2
{
}
// Namespace: System.Runtime.InteropServices
public static class Marshal // TypeDefIndex: 3
{
 // RVA: 0x100 Offset: 0x100 VA: 0x100
 internal static void copy_from_unmanaged(IntPtr source, int startIndex, Array destination, int length) { }
}
'''
  good='r.resolve(r.type("System.Runtime.InteropServices","Marshal"),"copy_from_unmanaged",{"System.IntPtr","System.Int32","System.Array","System.Int32"},true);'
  self.assertGreater(verify_sources(dump,[good]),0)
  with self.assertRaisesRegex(AssertionError,'Missing literal runtime overload'):
   verify_sources(dump,['r.resolve(r.type("System.Runtime.InteropServices","Marshal"),"Copy",{"System.IntPtr","System.Single[]","System.Int32","System.Int32"},true);'])
  with self.assertRaisesRegex(AssertionError,'Missing literal runtime overload'):
   verify_sources(dump,[good.replace(',true)',',false)')])
 def test_hp_failure_exits_without_a_result_coroutine(self):
  s=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  section=s[s.index('}else if(action==phimod::Action::TrackLost'):s.index('void onProgressUpdate(')]
  self.assertIn('r.string_new("SongSelector")',section)
  self.assertIn('"LevelBreak"',section)
  self.assertNotIn('"LevelOver"',section)
  self.assertNotIn('"StartCoroutine"',section)
  self.assertIn('attempt->acknowledgeAction(action)',section)
  self.assertIn('guard.store(true)',section)
 def test_reference_writes_use_direct_pointers_and_readback(self):
  s=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  self.assertIn('field_set_value(obj,f,value);',s)
  self.assertIn('field_static_set_value(f,value);',s)
  self.assertIn('else field_set_value(obj,f,&value);',s)
  self.assertIn('else field_static_set_value(f,&value);',s)
  self.assertIn('Instance reference readback failed:',s)
  self.assertIn('Static reference readback failed:',s)
  content=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('Content reference write preflight passed',content)
  self.assertIn('Content LoadScene begin:',content)
  self.assertIn('Chapter is empty;',content)
 def test_picker_copied_files_start_on_worker_independent_of_dismissal(self):
  s=(ROOT/'PhiMod/Sources/PMContentUI.mm').read_text(encoding='utf-8')
  method=s[s.index('- (void)importFiles'):s.index('- (void)export:')]
  self.assertIn('asCopy:YES',method)
  self.assertNotIn('asCopy:NO',method)
  batch=method.split('- (void)importSelectedURLs:',1)[1].split('- (void)documentPicker:',1)[0]
  self.assertNotIn('PMScopedFileAccess',batch)
  self.assertIn('self.importPicker=nil;picker.delegate=nil',batch)
  self.assertNotIn('completion:start',batch)
  self.assertIn('dispatch_async(self.worker',batch)
  self.assertIn('dispatch_async(self.worker',method)
  self.assertIn('dismissViewControllerAnimated:YES completion:start',method)
  self.assertIn('documentPickerWasCancelled:',method)
  self.assertIn('Content picker selected',method)
  self.assertIn('Content import begin:',method)
  self.assertIn('self.busy=NO',method)
 def test_texture_image_conversion_uses_managed_png_bytes(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  image=s[s.index('P image('):s.index('P audio(')]
  self.assertIn('UIImagePNGRepresentation(img)',image)
  self.assertIn('r.array_new(r.type("System","Byte")',image)
  self.assertIn('copy_from_unmanaged',image)
  self.assertIn('"ImageConversion"),"LoadImage"',image)
  self.assertIn('"UnityEngine.Texture2D","System.Byte[]","System.Boolean"',image)
  self.assertIn('r.call(texture,"get_width")',image);self.assertIn('r.call(texture,"get_height")',image)
  self.assertNotIn('LoadRawTextureData',image)
 def test_custom_chapter_cover_fallback_uses_loaded_sprite(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('applyCachedChapterCover',s);self.assertIn('syncChapterCoverFallbacks',s)
  self.assertIn('set_sprite',s);self.assertIn('chapterSelectorRoot=r.gchandle_new(self,false)',s)
  self.assertIn('syncChapterCoverFallbacks(r);',s[s.index('bool assetConstructor('):s.index('bool assetRelease(')])
 def test_practice_entry_suppresses_notes_until_range_reset(self):
  practice=(ROOT/'PhiMod/Sources/PMPractice.mm').read_text(encoding='utf-8')
  self.assertIn('bool entryLoading(Runtime&,P){return segment&&entryPending;}',practice)
  self.assertIn('get_activeSelf',practice)
  self.assertIn('skippedNotes=pmpracticepreview::reset',practice)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  manager=hook[hook.index('void onNoteManager('):hook.index('bool onBlocking(')]
  judge=hook[hook.index('void onJudgeUpdate('):hook.index('void onAddressableAudioUpdate(')]
  self.assertLess(manager.index('pmpractice::entryLoading'),manager.index('orig<VoidFn>(h::noteManager)'))
  self.assertLess(judge.index('pmpractice::entryLoading'),judge.index('orig<VoidFn>(h::judgeUpdate)'))
 def test_practice_prefix_is_settled_silently_for_manual_and_autoplay(self):
  source=(ROOT/'PhiMod/Sources/PMPracticePreview.mm').read_text(encoding='utf-8')
  self.assertIn('if(skipped){++skippedCount;settledNotes.insert(n.note);}',source)
  self.assertIn('r.put(n.note,"isJudged",skipped)',source)
  practice=(ROOT/'PhiMod/Sources/PMPractice.mm').read_text(encoding='utf-8')
  self.assertIn('r.put(score,"miss",autoplay?0:skippedNotes)',practice)
  self.assertIn('r.put(score,"perfect",autoplay?skippedNotes:0)',practice)
  self.assertIn('r.get<float>(note,"noteCode")+(autoplay?3.5f:0.f)',practice)
  self.assertIn('r.call(codes,"Clear")',practice)
  prefix=practice[practice.index('void prepareRange('):practice.index('void resumeAt(')]
  self.assertNotIn('r.call(score,"Miss"',prefix)
  self.assertNotIn('r.call(score,"Perfect"',prefix)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  create=hook[hook.index('void onCreateNote('):hook.index('void onNoteManager(')]
  self.assertIn('pmpracticepreview::settled(r.at(notes,index))',create)
  self.assertLess(create.index('pmpracticepreview::settled'),create.index('orig<void(*)(P,int,bool,P)>'))
  self.assertIn('skippedNotes==0',practice)
 def test_practice_transport_tap_activates_on_release(self):
  source=(ROOT/'PhiMod/Sources/PMPracticeControls.mm').read_text(encoding='utf-8')
  self.assertIn('transportAt:',source);self.assertIn('- (void)touchesEnded:',source)
  self.assertIn('[self activateTransport:pending]',source)
  self.assertIn('self.pressedTransport=-1',source)

 def test_content_batch_management_and_crop_entrypoints(self):
  ui=(ROOT/'PhiMod/Sources/PMContentUI.mm').read_text(encoding='utf-8')
  store=(ROOT/'PhiMod/Sources/PMContentStore.mm').read_text(encoding='utf-8')
  header=(ROOT/'PhiMod/Sources/PMContentStore.h').read_text(encoding='utf-8')
  self.assertIn('PMImageCropController.h',ui);self.assertIn('toggleBulkSelection',ui);self.assertIn('removeSelected',ui);self.assertIn('exportSelected',ui)
  self.assertIn('replaceImageData',ui);self.assertIn('removeSongs:ids',ui);self.assertIn('- (BOOL)removeSongs:',header);self.assertIn('- (BOOL)replaceImageData:',header)
  self.assertIn('dismissViewControllerAnimated:YES completion:start',ui)
  self.assertIn('if(ok)@synchronized(self){self.revision++;}',store)
 def test_dynamic_large_texture_preference_has_runtime_gate(self):
  settings=(ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8')
  runtime=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  self.assertIn('dynamicLargeTextures',settings);self.assertIn('PMSettingBool("dynamicLargeTextures")',runtime)
  image=runtime[runtime.index('P image('):runtime.index('P audio(')]
  self.assertIn('4096.0:2048.0',image);self.assertIn('64.0:32.0',image)
  self.assertIn('addSetting:@"dynamicLargeTextures"',ui)
 def test_resource_pack_entry_is_safe_and_explicit(self):
  ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  picker=(ROOT/'PhiMod/Sources/PMResourcePackUI.mm').read_text(encoding='utf-8')
  self.assertIn('PMResourcePackUI.h',ui);self.assertIn('openResourcePack',ui)
  self.assertIn('PMExtractArchive(temp,extract,&error)',picker)
  for item in ('click.png','drag.png','flick.png','hold.png'):self.assertIn(item,picker)
  self.assertIn('128ull*1024*1024',picker);self.assertIn('runtime application is gated separately',picker)
  self.assertIn('dispatch_async(self.worker',picker);self.assertIn('startAccessingSecurityScopedResource',picker);self.assertIn('picker.presentingViewController',picker)
 def test_custom_drawer_visibility_is_persisted_and_compacted(self):
  settings=(ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8');scene=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8');ui=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  for key in ('shortcutAutoPlay','shortcutNoise','shortcutUnified','shortcutChallenge','shortcutHp','shortcutFullScreen','shortcutAccuracy'):self.assertIn(key,settings);self.assertIn(key,ui)
  self.assertIn('shortcutVisible(NSDictionary*s,int i)',scene);self.assertIn('activeIndices',scene);self.assertIn('bool supported=shortcutVisible(s,i)',scene)
 def test_release_resource_uses_custom_cleanup_and_preserves_new_owners(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  release=s[s.index('bool assetRelease('):s.index('void levelInfo(')]
  self.assertIn('if(!force&&n>1)',release)
  self.assertIn('"get_Item",{"System.String"},{key})==self',release)
  self.assertIn('if(it!=refs.end())',release)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('pmcontent::assetRelease(R(),self,true)',hook)
  self.assertIn('orig<VoidFn>(h::assetReleaseResource)(self,mi)',hook)
  self.assertIn('reinterpret_cast<P>(onAssetReleaseResource)',hook)
 def test_chapters_are_hidden_by_cards_not_destroying_songs(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  apply=s[s.index('void apply('):s.index('P image(')]
  self.assertNotIn('hiddenChapters',apply)
  prepare=s[s.index('void chapterPrepare('):s.index('void chapterReady(')]
  for contract in ('hiddenChapters','GetComponentsInChildren','Instantiate','SetSiblingIndex','_chapterInfos','coverAssetCode','coverBlurAssetCode'):
   self.assertIn(contract,prepare)
  self.assertLess(prepare.index('Instantiate'),prepare.index('for(P card:original){bool visible='))
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  start=hook[hook.index('void onChapterStart('):hook.index('P onSongInfo(')]
  self.assertLess(start.index('pmcontent::chapterPrepare'),start.index('orig<VoidFn>'))
  self.assertLess(start.index('orig<VoidFn>'),start.index('pmcontent::chapterReady'))
 def test_native_chart_does_not_leak_visual_metadata(self):
  s=(ROOT/'PhiMod/Sources/PMChartConvert.mm').read_text(encoding='utf-8')
  native=s[s.index('NSDictionary*PMNativeChart('):]
  self.assertIn('chart[@"blockAreaList"] ?: @[]',native)
  self.assertNotIn('[chart mutableCopy]',native)
  self.assertNotIn('[line mutableCopy]',native)
  self.assertIn('if(![n[@"pmFake"] boolValue])',native)
 def test_bridge_checks_value_type_and_size(self):
  s=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  self.assertIn('class_value_size(c,&alignment)!=sizeof(T)',s)
  self.assertIn('checkClass<T>(class_from_type(field_get_type(f)))',s)
  self.assertIn('checkClass<T>(object_get_class(obj))',s)
if __name__=='__main__':unittest.main()
