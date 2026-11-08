import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHA = "1234567890abcdef1234567890abcdef12345678"


class ReleaseTests(unittest.TestCase):
    def test_release_pins_the_built_sha_and_personal_account(self):
        with tempfile.TemporaryDirectory(prefix="toma-release-test-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy(REPO / "scripts/release.sh", root / "scripts/release.sh")
            shutil.copy(REPO / "scripts/signing.py", root / "scripts/signing.py")
            if (REPO / "scripts/github.sh").exists():
                shutil.copy(REPO / "scripts/github.sh", root / "scripts/github.sh")
            (root / "VERSION").write_text("1.3.1\n")
            (root / "CHANGELOG.md").write_text(
                "## [1.3.1]\n\nFix recording recovery.\n"
            )
            (root / "build.sh").write_text(
                '#!/bin/sh\nprintf "%s" "$BUILD_COMMIT_SHA" > built-sha\n'
            )
            (root / "build.sh").chmod(0o755)
            tools = root / "bin"
            tools.mkdir()
            stub = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name=Path(sys.argv[0]).name
args=sys.argv[1:]
if name == 'git':
 if args[:2] == ['branch','--show-current']: print('main')
 elif args and args[0] == 'rev-parse':
  if args[-1] in ('HEAD','origin/main'): print(os.environ['TEST_SHA'])
  else: sys.exit(1)
elif name == 'gh':
 if args[:2] == ['auth','token']: print('fixture-token')
 elif args[:2] == ['api','user']: print('eherrerosj')
 elif args[:2] == ['release','view']: sys.exit(1)
 elif args[:2] == ['release','create']: Path('release-args.json').write_text(json.dumps(args))
elif name == 'security':
 if args[0] == 'find-identity': print('1) ' + 'A' * 40 + ' "Developer ID Application: Fixture (ABCDEFGHIJ)"')
 elif args[0] == 'find-certificate': print('-----BEGIN CERTIFICATE-----\\nZmFrZQ==\\n-----END CERTIFICATE-----')
elif name == 'openssl':
 print('sha1 Fingerprint=' + ':'.join(['AA'] * 20))
 print('subject=CN=Fixture,OU=ABCDEFGHIJ,O=Fixture')
elif name == 'plutil': print(os.environ['TEST_SHA'])
"""
            for name in ["git", "gh", "xcrun", "plutil", "security", "openssl"]:
                (tools / name).write_text(stub)
                (tools / name).chmod(0o755)
            env = dict(
                os.environ,
                PATH=str(tools) + os.pathsep + os.environ["PATH"],
                TEST_SHA=SHA,
                SIGNING_IDENTITY="Developer ID Application: Fixture (ABCDEFGHIJ)",
                SIGNING_TEAM="ABCDEFGHIJ",
            )
            run = subprocess.run(
                ["sh", "scripts/release.sh"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            args = json.loads((root / "release-args.json").read_text())
            self.assertEqual(args[args.index("--target") + 1], SHA)
            self.assertEqual((root / "built-sha").read_text(), SHA)
            self.assertEqual(args[args.index("--repo") + 1], "eherrerosj/toma")

    def test_packaging_discovers_the_output_path(self):
        source = (REPO / "build.sh").read_text()
        self.assertNotIn("cp .build/apple/Products/Release/Toma", source)
        self.assertIn("--show-bin-path -c release --arch arm64 --arch x86_64", source)


if __name__ == "__main__":
    unittest.main()
