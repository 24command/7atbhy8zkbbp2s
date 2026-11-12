"""Verify iOS gameplay ABI/reflection contracts against the supplied iOS dump.
The dump is not shipped. This is a static check, not Apple/device verification.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HP_NS = 'Phigros2.Level.Mods.SecretChallengeLife.'
ALIASES = {name: HP_NS + name for name in ('SecretChallengeLifeBar', 'SecretChallengeLifeMod')}
ALIASES.update(Button='UnityEngine.UI.Button', JsonUtility='UnityEngine.JsonUtility',
               Array='System.Array', Mathf='UnityEngine.Mathf', AudioSource='UnityEngine.AudioSource', Time='UnityEngine.Time', Object='UnityEngine.Object',
               PreviewBlockControl='ProjectEditor.PreviewScripts.PreviewBlockControl',
               PreviewElementUpdateControl='Phigros2.Level.Scripts.PreviewElementUpdateControl')

# Types are the dump's C# spellings, not hardcoded Android memory offsets.
FIELDS = {
 'Chart': {'judgeLineList':'List<JudgeLine>', 'blockAreaList':'List<GameInformation.BlockArea>'},
 'ChartNote': dict(type='int', time='int', speed='float', holdTime='float', positionX='float', realTime='float', noteCode='float'),
 'JudgeLine': dict(bpm='float', speedEvents='List<SpeedEvent>', notesAbove='List<ChartNote>', notesBelow='List<ChartNote>'),
 'SpeedEvent': dict(startTime='float', value='float'),
 'LevelControl': dict(chart='Chart', previewElementUpdateControl='PreviewElementUpdateControl', scoreControl='ScoreControl'),
 'LevelStartInfo': dict(levelMods='List<string>'),
 'PreviewElementUpdateControl': {'previewBlocks':'List<PreviewBlockControl>', '<BlockRender>k__BackingField':'BlockRender', 'screenWidth':'float', 'screenHeight':'float'},
 'PreviewBlockControl': dict(blockInfo='GameInformation.BlockArea'),
 'GameInformation.BlockArea': dict(topRightPercentage='Vector2', bottomLeftPercentage='Vector2', isSubtract='bool', appearTime='float', enableTime='float', disableTime='float', disappearTime='float'),
 'BlockRender': dict(activeBlockMaterial='Material', effectRT='RenderTexture', composedEnabledBlockRT='RenderTexture', composedDisabledBlockRT='RenderTexture'),
 'JudgeLineControl': dict(numOfFingers='int', fingerPositionX='float[]'),
 'NoteUpdateManager': dict(progressControl='ProgressControl'),
 'SecretChallengeLifeBar': dict(target='RawImage', materialTemplate='Material', runtimeMaterial='Material', lifeCanvas='Canvas', maximumLife='int', displayedLife='float', lifeVelocity='float', shrinkSmoothTime='float'),
 'SecretChallengeLifeMod': dict(levelControl='LevelControl', scoreControl='ScoreControl', redFlash='GameObject', subscribed='bool', failed='bool', lifeHitFlash='Coroutine'),
 'LevelOverControl.<>c__DisplayClass43_0': {'<>4__this':'LevelOverControl', 'record':'LevelRecord'},
 'LevelOverControl.<Start>d__43': {'<>1__state':'int', '<>2__current':'object', '<>4__this':'LevelOverControl'},
 'LevelResultInfo': {'<IntScore>k__BackingField':'int'},
}
for name in ('ClickControl', 'DragControl', 'HoldControl', 'FlickControl'):
 FIELDS[name] = dict(noteInfor='ChartNote', isVisible='bool', progressControl='ProgressControl', judgeLine='JudgeLineControl')
FIELDS['HoldControl'].update(judged='bool', missed='bool', timeOfJudge='float')

# Helper overloads invoked reflectively. Each tuple is (name, parameters, static).
METHODS = {
 'System.Runtime.InteropServices.Marshal': [('copy_from_unmanaged','IntPtr,int,Array,int',True)],
 'UnityEngine.AudioClip': [('Create','string,int,int,int,bool',True), ('SetData','float[],int',False)],
 'JsonUtility': [('ToJson','object',True), ('FromJson','string,Type',True), ('FromJsonOverwrite','string,object',True)],
 'Array': [('GetValue','int',False), ('SetValue','object,int',False)],
 'Mathf': [('SmoothDamp','float,float,float&,float,float,float',True)],
 'PreviewBlockControl': [('UpdateBlocksTransform','',False)],
 'BlockRender': [('ClearRenderTexture','RenderTexture',True)],
 'SecretChallengeLifeBar': [('ConfigureCanvas','',False), ('ApplyShaderParameters','',False)],
 'SecretChallengeLifeMod': [('FlashLifeText','',False), ('AudioFadeOut','AddressableAudioSource,float',False), ('EnableTrueShadow','Component',True)],
 'HPDisplayControl': [(prefix+name, '' if prefix=='get_' else typ, True)
                      for name,typ in [('MainColor','Color'), ('CoverColor','Color'), ('Opacity','float'), ('GlowOpacity','float')]
                      for prefix in ('get_', 'set_')] + [('set_HP','float',True)],
 'LevelOverControl.<>c__DisplayClass43_0': [(name,'',False) for name in (
  '<Start>g__SetResultAudio|1', '<Start>g__SetResultInfo|2', '<Start>g__SetScreenRatio|23',
  '<Start>g__EnableResultCanvas|21', '<Start>g__PlayResultBGM|22')]
  + [('<Start>g__SetRatingWithScore|3','int,bool',False)],
 'AddressableAudioSource': [('set_Volume','float',False), ('Stop','',False), ('Play','',False), ('Pause','',False), ('Seek','float',False), ('get_ClipLength','',False)],
 'ProgressControl': [('LevelBreak','string',False), ('LevelOver','',False), ('Play','bool',False)],
 'ScoreControl': [('FreezeScore','',False), ('SetNoteCodeList','',False)],
 'AudioSource': [('get_pitch','',False), ('set_pitch','float',False), ('get_time','',False), ('set_time','float',False)],
 'Time': [('get_timeSinceLevelLoad','',True)],
 'Object': [('Destroy','UnityEngine.Object',True)],
}
SERIALIZABLE = ('Chart', 'ChartNote', 'JudgeLine', 'SpeedEvent', 'GameInformation.BlockArea')


def index_dump(dump):
 types = {}
 for chunk in dump.split('// Namespace: ')[1:]:
  namespace, _, body = chunk.partition('\n')
  decl = re.search(r'^(?:(?:public|private|internal|protected|sealed|abstract|static|partial|readonly)\s+)+(?:class|struct|interface|enum)\s+(.+?) // TypeDefIndex: \d+', body, re.M)
  if not decl:
   continue
  name = decl[1].split(' : ', 1)[0].strip()
  full = (namespace.strip()+'.' if namespace.strip() else '')+name
  if full in types:
   types[full] = None  # Repeated <Module>/cross-assembly names may not be queried.
   continue
  types[full] = (body[decl.end():], body[:decl.start()])
 return types


def parameters(text):
 result = []
 for item in text.split(','):
  item = item.strip()
  if not item:
   continue
  tokens = item.split('=',1)[0].split()
  byref = tokens[0] in ('ref','out','in')
  if byref:
   tokens = tokens[1:]
  typ = tokens[0].removeprefix('UnityEngine.')
  if byref:
   typ += '&'
  result.append(typ)
 return result


def method_matches(body, name, args, static):
 pattern = r'^\s*((?:(?:public|private|internal|protected|static|virtual|override|sealed|abstract|extern|new)\s+)+)(\S+)\s+'+re.escape(name)+r'\(([^\n]*)\) \{ \}'
 for match in re.finditer(pattern, body, re.M):
  if parameters(match[3]) != parameters(args):
   continue
  if static is not None and ('static' in match[1].split()) != static:
   continue
  rvas = re.findall(r'// RVA: (0x[\dA-Fa-f]+|-[0-9]+)', body[:match.start()])
  yield match[2], int(rvas[-1], 0) if rvas else None


def verify(dump, manifest):
 types = index_dump(dump)
 def body(name):
  full = ALIASES.get(name,name)
  assert full in types and types[full] is not None, 'Missing or ambiguous exact type: '+full
  return types[full][0]
 count = 0
 for name,fields in FIELDS.items():
  text = body(name)
  for field,typ in fields.items():
   # Instance fields only. Static or renamed fields must fail the audit.
   pattern = r'^\s*(?:public|private|internal|protected)\s+(?:readonly\s+)?'+re.escape(typ)+r'\s+'+re.escape(field)+r'; //'
   assert re.search(pattern,text,re.M), f'Field contract mismatch: {name}.{field}: {typ}'
   count += 1
 for name in SERIALIZABLE:
  assert '[Serializable]' in types[ALIASES.get(name,name)][1], 'Chart clone not serializable: '+name
  count += 1
 for name,methods in METHODS.items():
  for method,args,static in methods:
   matches = list(method_matches(body(name),method,args,static))
   assert len(matches)==1, f'Method contract mismatch: {name}.{method}({args}), static={static}'
   count += 1
 for entry in manifest:
  if entry['id'] in ('assetCtor','assetRelease','assetReleaseResource'):
   # IL2CPP's shared generic code has an RVA in GenericInstMethod rather
   # than on the open generic C# declaration. Verify that exact shared body.
   name='AssetStore.AssetRef<T>'
   text=body(name)
   method={'assetCtor':'.ctor','assetRelease':'Release','assetReleaseResource':'ReleaseResource'}[entry['id']]
   expected='AssetStore.AssetRef<object>.'+method
   assert entry['name']==expected, 'Generic hook name mismatch'
   marker='|-'+expected
   at=text.find(marker)
   assert at>=0, 'Shared generic instantiation missing: '+expected
   rvas=re.findall(r'\|-RVA: (0x[0-9A-Fa-f]+)',text[:at])
   assert rvas and int(rvas[-1],16)==entry['rva'], 'Shared generic RVA mismatch'
   assert re.search(r'(?:public|private) void '+re.escape(method)+r'\(',text), 'Generic signature missing'
   count+=1
   continue
  name,method = entry['name'].rsplit('.',1)
  matches = list(method_matches(body(name),method,entry['args'],None))
  assert len(matches)==1, 'Hook signature mismatch: '+entry['name']
  result,rva = matches[0]
  assert rva==entry['rva'], 'Hook RVA mismatch: '+entry['name']
  if entry['id'] in ('click','drag','hold','flick','resultMove','blocking'):
   assert result=='bool', 'Hook result mismatch: '+entry['name']
  if entry['id']=='lifeNormalized':
   assert result=='float', 'Hook result mismatch: '+entry['name']
  count += 1
 return count



def canonical_type(spelling, types):
 spelling = spelling.strip()
 primitives = dict(bool='System.Boolean', int='System.Int32', float='System.Single',
                   string='System.String', object='System.Object', long='System.Int64',
                   double='System.Double', byte='System.Byte', char='System.Char',
                   uint='System.UInt32', ulong='System.UInt64', short='System.Int16',
                   ushort='System.UInt16', sbyte='System.SByte')
 if spelling in primitives:
  return primitives[spelling]
 if spelling.endswith('&'):
  return canonical_type(spelling[:-1],types)+'&'
 if spelling.endswith('[]'):
  return canonical_type(spelling[:-2],types)+'[]'
 if spelling.startswith('List<') and spelling.endswith('>'):
  return 'System.Collections.Generic.List<'+canonical_type(spelling[5:-1],types)+'>'
 if '<' in spelling and spelling.endswith('>'):
  base,arguments=spelling[:-1].split('<',1)
  candidates={key.split('<',1)[0] for key,value in types.items() if value is not None and '<' in key and (key.split('<',1)[0]==base or key.split('<',1)[0].endswith('.'+base))}
  assert len(candidates)==1, 'Cannot resolve generic type: '+spelling
  return candidates.pop()+'<'+','.join(canonical_type(t.strip(),types) for t in arguments.split(','))+'>'
 if spelling in types and types[spelling] is not None:
  return spelling
 if 'System.'+spelling in types:
  return 'System.'+spelling
 # The dump uses unqualified Unity field types throughout Assembly-CSharp.
 if 'UnityEngine.'+spelling in types:
  return 'UnityEngine.'+spelling
 candidates = [key for key,value in types.items() if value is not None and key.endswith('.'+spelling)]
 assert len(candidates)==1, 'Cannot resolve dump field type: '+spelling
 return candidates[0]


def verify_sources(dump, sources):
 """Audit literal runtime class lookups and typed field preflight calls.
 Dynamic loop contracts are covered separately above and by device fail-closed checks.
 """
 types = index_dump(dump)
 count = 0
 for source in sources:
  for name in re.findall(r'\br\.klass\("([^"]+)"\)',source):
   assert name in types and types[name] is not None, 'Invalid root-namespace runtime lookup: '+name
   count += 1
  for namespace,name in re.findall(r'\br\.type\("([^"]*)","([^"]+)"\)',source):
   full = namespace+'.'+name if namespace else name
   assert full in types and types[full] is not None, 'Invalid qualified runtime lookup: '+full
   count += 1
  lookup = r'r\.(?:klass\("(?P<root>[^"]+)"\)|type\("(?P<ns>[^"]*)","(?P<name>[^"]+)"\))'
  pattern = r'r\.field\('+lookup+r',"(?P<field>[^"]+)","(?P<typ>[^"]+)",(?P<static>true|false)\)'
  for match in re.finditer(pattern,source):
   full = match['root'] or ((match['ns']+'.') if match['ns'] else '')+match['name']
   body = types[full][0]
   declaration = re.search(r'^\s*(?:public|private|internal|protected)\s+(?P<static>static\s+)?(?:readonly\s+)?(?P<type>[^;\n]+?)\s+'+re.escape(match['field'])+r'; //',body,re.M)
   assert declaration, 'Missing preflight field: '+full+'.'+match['field']
   assert bool(declaration['static'])==(match['static']=='true'), 'Static flag mismatch: '+full+'.'+match['field']
   spelling=declaration['type']
   overrides = {('ChapterInfo','play','Button'):'UnityEngine.UI.Button', ('AddressableImageLoader','_image','Image'):'UnityEngine.UI.Image'}
   expected = overrides.get((full,match['field'],spelling)) or canonical_type(spelling,types)
   assert match['typ']==expected, f'Runtime field namespace/type mismatch: {full}.{match["field"]}: {match["typ"]} != {expected}'
   count += 1
  # These literal method calls were previously unchecked: a class could exist
  # while its requested overload had been stripped from the iOS player.
  call = r'r\.(?P<op>resolve|stat)\(\s*'+lookup+r'\s*,\s*"(?P<method>[^"]+)"\s*(?:,\s*\{(?P<params>[^{}]*)\})?(?:\s*,\s*(?P<isstatic>true|false))?'
  for match in re.finditer(call,source):
   full = match['root'] or ((match['ns']+'.') if match['ns'] else '')+match['name']
   expected = re.findall(r'"([^"]+)"',match['params'] or '')
   isstatic = match['op']=='stat' or match['isstatic']=='true'
   pattern = r'^\s*((?:(?:public|private|internal|protected|static|virtual|override|sealed|abstract|extern|new)\s+)+)(\S+)\s+'+re.escape(match['method'])+r'\(([^\n]*)\) \{ \}'
   found = False
   for declaration in re.finditer(pattern,types[full][0],re.M):
    if ('static' in declaration[1].split()) != isstatic:
     continue
    actual = []
    for parameter in declaration[3].split(','):
     tokens=parameter.split('=',1)[0].split()
     if tokens:
      byref=tokens[0] in ('ref','out','in')
      actual.append(tokens[1]+'&' if byref else tokens[0])
    if len(actual)!=len(expected):
     continue
    try:
     namespace=full.rpartition('.')[0]
     def qualify(t):
      if t.endswith('[]'):return qualify(t[:-2])+'[]'
      if t.endswith('&'):return qualify(t[:-1])+'&'
      local=namespace+'.'+t
      return local if local in types and types[local] is not None else canonical_type(t,types)
     canonical = [qualify(t) for t in actual]
    except AssertionError:
     continue  # Unsupported generic candidate cannot match this literal signature.
    if canonical==expected:
     found=True;break
   assert found, f'Missing literal runtime overload: {full}.{match["method"]}({expected}), static={isstatic}'
   count += 1
 return count


def main():
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('dump',type=Path)
 args = parser.parse_args()
 dump = args.dump.read_text(encoding='utf-8-sig')
 manifest = json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
 count = verify(dump,manifest)
 sources = [(ROOT/"PhiMod/Sources"/name).read_text(encoding="utf-8") for name in ("PMChartModes.mm", "PMHPLife.mm", "PMPractice.mm", "PMPracticePreview.mm", "PMContentRuntime.mm", "PMRPEHudRuntime.inc", "PMRPESkewRuntime.inc", "PMHookBackend.mm", "PMSceneUI.mm", "PMRuntime.mm", "PMUnlockRuntime.mm", "PMUnlockDetails.inc")]
 source_count = verify_sources(dump,sources)
 for old,new in [('public ChartNote noteInfor;', 'public ChartNote noteInfo;'),
                 ('public float timeOfJudge;', 'public double timeOfJudge;'),
                 ('public int time;','public float time;')]:
  assert old in dump, 'Negative fixture not present: '+old
  try:
   verify(dump.replace(old,new),manifest)
  except AssertionError:
   pass
  else:
   raise AssertionError('Failed to reject changed metadata: '+old)
 for old,new in [('r.type("ProjectEditor.PreviewScripts","PreviewBlockControl")', 'r.klass("PreviewBlockControl")'),
                 ('System.Collections.Generic.List<ProjectEditor.PreviewScripts.PreviewBlockControl>', 'System.Collections.Generic.List<PreviewBlockControl>')]:
  assert any(old in source for source in sources), 'Source fixture not found: '+old
  try:
   verify_sources(dump,[source.replace(old,new) for source in sources])
  except AssertionError:
   pass
  else:
   raise AssertionError('Failed to reject incorrect runtime namespace: '+old)
 # Regression for the framework14 startup blocker: must fail before shipping.
 try:
  verify_sources(dump,['r.resolve(r.type("System.Runtime.InteropServices","Marshal"),"Copy",{"System.IntPtr","System.Single[]","System.Int32","System.Int32"},true);'])
 except AssertionError:
  pass
 else:
  raise AssertionError('Accepted stripped Marshal.Copy Single[] overload')
 print(f'PASS: {count} gameplay metadata / {len(manifest)} hook contracts + {source_count} source lookups + 6 negative fixtures')

if __name__=='__main__':
 main()
