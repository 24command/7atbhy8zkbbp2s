import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ROOT / "PhiMod" / "Sources"

class ResumeIntegrityTests(unittest.TestCase):
    def test_sources_decode_and_no_disconnect_placeholders(self):
        for path in SOURCES.iterdir():
            if path.suffix not in (".mm", ".h", ".hpp", ".cpp"):
                continue
            text = path.read_text(encoding="utf-8-sig")
            self.assertNotIn("\ufffd", text, str(path))
            self.assertNotIn("????", text, str(path))

    def test_objective_cpp_regressions(self):
        text = (SOURCES / "PMContentStore.mm").read_text(encoding="utf-8-sig")
        for invalid in ("x.lengthOfBytesUsingEncoding:", "__block std::function", "seenSongs[sid]", "cid==loose"):
            self.assertNotIn(invalid, text)
        self.assertIn("manifestSafePath(name)", text)
        self.assertIn("graphLimitExceeded", text)
        self.assertIn("validateUnlockMedia(sourceChapter", text)

if __name__ == "__main__":
    unittest.main()
