"""Static dump/source contract checks. Does NOT replace Apple compilation or device tests."""
import argparse
from pathlib import Path
import re


def block(dump, name):
    match = re.search(r'^public class ' + re.escape(name) + r'(?: :[^\n]+)? //[^\n]*\n\{', dump, re.M)
    assert match, f'Missing exact type: {name}'
    end = dump.find('\n// Namespace:', match.start())
    return dump[match.start():end if end >= 0 else len(dump)]


def verify(dump, source):
    contracts = {
        'MultiLanguageManager': [
            'public static void SetLanguage(SystemLanguage _language)',
            'public static SystemLanguage GetCurrentLanguage()',
        ],
        'JudgeControl': [
            'public static float PerfectTimeRange;',
            'public static float GoodTimeRange;',
            'public static float BadTimeRange;',
            'public static bool InChallengeMode;',
        ],
        'GameInformation': [
            'private static GameInformation _main;',
            'private float <RankingScore>k__BackingField;',
        ],
    }
    for name, declarations in contracts.items():
        text = block(dump, name)
        for declaration in declarations:
            assert declaration in text, f'Contract mismatch: {name}.{declaration}'
    assert 'field_static_set_value' in source, 'Judge settings backend must expose static field writes'
    assert 'applyJudgeSettings' in source, 'Judge settings writes must be behind the explicit apply method'
    assert 'field_static_set_value(pf' in source and 'field_static_set_value(gf' in source and 'field_static_set_value(bf' in source, 'Judge writes must cover P/G/B fields'
    assert 'runtime_class_init(judge)' in source, 'Initialize JudgeControl before writing windows'
    assert 'judgePatch(true)' in source, 'Missing offline hook must not claim success'
    assert 'controller.apply(*patch' in source, 'Use the tested transactional readback controller'
    assert 'judgeVerified' in source and 'judgeHookReady' in source
    core=(Path(__file__).resolve().parents[1]/'PhiMod/Core/PMJudgeCore.hpp').read_text(encoding='utf-8')
    assert 'matches(actual,desired)' in core and 's.enabled=0' in core
    assert 'native/offsets.h' not in source
    assert 'runtime_invoke' in source and 'method_get_param' in source
    assert 'isMainThread' in source and 'ownedThread' in source
    assert 'if (exception)' in source and 'Unsupported UnityFramework UUID' in source
    return sum(map(len, contracts.values()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    args = parser.parse_args()
    source = (Path(__file__).resolve().parents[1] / 'PhiMod/Sources/PMRuntime.mm').read_text(encoding='utf-8')
    dump = args.dump.read_text(encoding='utf-8-sig')
    count = verify(dump, source)
    # Negative fixtures must be rejected, not silently accepted.
    for old, new in [('public static float PerfectTimeRange;', 'public float PerfectTimeRange;'),
                     ('SetLanguage(SystemLanguage _language)', 'SetLanguage(int _language)'),
                     ('private static GameInformation _main;', 'private GameInformation _main;')]:
        assert old in dump
        try:
            verify(dump.replace(old, new), source)
        except AssertionError:
            pass
        else:
            raise AssertionError('Failed to reject incompatible fixture: ' + old)
    print(f'PASS: {count} dump contracts + 3 negative fixtures + source guard checks')
