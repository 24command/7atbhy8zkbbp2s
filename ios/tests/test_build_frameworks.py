"""Guard explicit system framework linkage; not an Apple SDK link test."""
import re
import unittest
from pathlib import Path

class BuildFrameworks(unittest.TestCase):
    def test_media_frameworks_are_in_the_link_command(self):
        script = (Path(__file__).resolve().parents[1] / "build_unsigned.sh").read_text(encoding="utf-8")
        command = script.split("xcrun --sdk iphoneos clang++", 1)[1].split('cp "$ROOT/', 1)[0]
        frameworks = re.findall(r"-framework\s+(\w+)", command)
        for name in ("ImageIO", "CoreMedia", "AVFoundation"):
            self.assertEqual(frameworks.count(name), 1, name)
        self.assertNotIn("-undefined dynamic_lookup", command)
        self.assertIn('"$ROOT"/PhiMod/Sources/*.mm', command)

if __name__ == "__main__":
    unittest.main()
