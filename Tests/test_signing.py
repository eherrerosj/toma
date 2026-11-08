import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CERT = "A" * 40
TEAM = "ABCDEFGHIJ"
NAME = "Apple Development: Fixture (PERSON1234)"


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="toma-signing-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        binary = self.root / "bin"
        binary.mkdir()
        stub = """#!/usr/bin/env python3
import os, sys
from pathlib import Path
if Path(sys.argv[0]).name == 'security':
 if sys.argv[1] == 'find-identity':
  print(os.environ.get('TEST_IDENTITIES', ''))
 elif sys.argv[1] == 'find-certificate':
  print('-----BEGIN CERTIFICATE-----\\nZmFrZQ==\\n-----END CERTIFICATE-----')
else:
 print('sha1 Fingerprint=' + ':'.join(['AA'] * 20))
 print('subject=CN=Fixture,OU=' + os.environ.get('TEST_TEAM', 'ABCDEFGHIJ') + ',O=Fixture')
"""
        for name in ["security", "openssl"]:
            path = binary / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=str(binary) + os.pathsep + os.environ["PATH"],
            TEST_IDENTITIES=f'  1) {CERT} "{NAME}"\n',
            TEST_TEAM=TEAM,
        )
        for key in [
            "SIGNING_IDENTITY",
            "SIGNING_TEAM",
            "SIGNING_MODE",
            "REQUIRE_NOTARIZATION",
        ]:
            self.env.pop(key, None)

    def run_signing(self, *args, **env):
        return subprocess.run(
            ["python3", str(REPO / "scripts/signing.py"), *args],
            cwd=self.root,
            env=dict(self.env, **env),
            text=True,
            capture_output=True,
        )

    def configure(self):
        result = self.run_signing("configure", "--identity", CERT, "--team", TEAM)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_persists_one_explicit_certificate_and_team(self):
        self.configure()
        result = self.run_signing("resolve")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"{CERT} {TEAM} development")
        stored = subprocess.check_output(
            ["git", "config", "--local", "toma.signingIdentity"],
            cwd=self.root,
            text=True,
        )
        self.assertEqual(stored.strip(), CERT)

    def test_verify_passes_an_inline_requirement_to_codesign(self):
        self.configure()
        codesign = self.root / "bin/codesign"
        codesign.write_text("""#!/usr/bin/env python3
import sys
args = sys.argv[1:]
rule = args[args.index('-R') + 1]
valid = rule.startswith('=anchor apple generic')
valid = valid and 'subject.OU' in rule and 'io.github.eherrerosj.toma' in rule
if not valid:
 sys.exit(1)
""")
        codesign.chmod(0o755)
        result = self.run_signing("verify", "/unused.app")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_pinned_identity_never_falls_back_to_adhoc(self):
        self.configure()
        result = self.run_signing("resolve", TEST_IDENTITIES="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unavailable", result.stderr)
        self.assertNotIn("- - adhoc", result.stdout)

    def test_rejects_certificate_from_another_team(self):
        result = self.run_signing(
            "configure", "--identity", CERT, "--team", "WRONGTEAM1"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("team", result.stderr)
        stored = subprocess.run(
            ["git", "config", "--local", "--get", "toma.signingIdentity"], cwd=self.root
        )
        self.assertNotEqual(stored.returncode, 0)

    def test_ambiguous_names_require_a_fingerprint(self):
        identities = f'1) {CERT} "{NAME}"\n2) {"B" * 40} "{NAME}"\n'
        result = self.run_signing(
            "resolve",
            SIGNING_IDENTITY=NAME,
            SIGNING_TEAM=TEAM,
            TEST_IDENTITIES=identities,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ambiguous", result.stderr)

    def test_adhoc_requires_deliberate_override_after_configuration(self):
        self.configure()
        result = self.run_signing("resolve", SIGNING_IDENTITY="-")
        self.assertNotEqual(result.returncode, 0)
        result = self.run_signing("resolve", SIGNING_MODE="adhoc")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "- - adhoc")

    def test_unreadable_configuration_cannot_turn_a_stable_build_into_adhoc(self):
        git = self.root / "bin/git"
        git.write_text("#!/bin/sh\nexit 2\n")
        git.chmod(0o755)
        result = self.run_signing("resolve")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing an ad hoc fallback", result.stderr)

    def test_notarization_rejects_development_and_adhoc(self):
        self.configure()
        for settings in [{}, {"SIGNING_MODE": "adhoc"}]:
            result = self.run_signing("resolve", REQUIRE_NOTARIZATION="1", **settings)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Developer ID", result.stderr)

    def test_unconfigured_smoke_build_stays_adhoc_and_stable_mode_requires_setup(self):
        result = self.run_signing("resolve")
        self.assertEqual(result.stdout.strip(), "- - adhoc")
        result = self.run_signing("resolve", SIGNING_MODE="stable")
        self.assertNotEqual(result.returncode, 0)

    def test_build_preflight_preserves_previous_artifact_when_signer_is_missing(self):
        (self.root / "scripts").mkdir()
        shutil.copy(REPO / "scripts/signing.py", self.root / "scripts/signing.py")
        shutil.copy(REPO / "build.sh", self.root / "build.sh")
        app = self.root / "Toma Personal.app"
        app.mkdir()
        previous = app / "previous-build"
        previous.write_text("Keep this until signing preflight passes.")
        swift = self.root / "bin/swift"
        swift.write_text("#!/bin/sh\ntouch unexpected-build\nexit 1\n")
        swift.chmod(0o755)
        result = subprocess.run(
            ["sh", "build.sh"],
            cwd=self.root,
            env=dict(self.env, SIGNING_IDENTITY="B" * 40, SIGNING_TEAM=TEAM),
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unavailable", result.stderr)
        self.assertTrue(previous.exists())
        self.assertFalse((self.root / "unexpected-build").exists())

    def test_developer_id_identity_can_pass_release_preflight(self):
        name = "Developer ID Application: Fixture (ABCDEFGHIJ)"
        result = self.run_signing(
            "resolve",
            SIGNING_IDENTITY=CERT,
            SIGNING_TEAM=TEAM,
            TEST_IDENTITIES=f'1) {CERT} "{name}"\n',
            REQUIRE_NOTARIZATION="1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"{CERT} {TEAM} developer-id")

    def test_unknown_mode_and_local_self_signed_identity_are_rejected(self):
        self.assertNotEqual(
            self.run_signing("resolve", SIGNING_MODE="typo").returncode, 0
        )
        result = self.run_signing(
            "resolve",
            SIGNING_IDENTITY=CERT,
            SIGNING_TEAM=TEAM,
            TEST_IDENTITIES=f'1) {CERT} "Unrelated Local Dev"\n',
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
