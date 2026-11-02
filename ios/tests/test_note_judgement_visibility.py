from pathlib import Path
s=(Path(__file__).resolve().parents[1]/"PhiMod/Sources/PMContentRuntime.mm").read_text(encoding="utf-8")
start=s.index("void noteMoved(")
end=s.index("void finishNoteGeometry(",start)
s=s[start:end]
assert s.index("if(ended)") < s.index('r.call(tr,"set_localScale"')
assert 'if(sourceGeometry&&!controlMissed' in s
assert 'color.a=(sourceGeometry&&!controlMissed)?alpha:std::min(color.a,alpha);' in s
assert 'std::vector<const char*>{{' not in s
assert 'catch(...)' not in s
print("PASS terminal controller guard, miss-fade preservation, and continuous source alpha")
