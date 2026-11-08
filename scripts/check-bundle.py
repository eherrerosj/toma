#!/usr/bin/env python3
import plistlib
import subprocess
from pathlib import Path

from signing import resolve, verify

app = Path("Toma Personal.app")
with (app / "Contents/Info.plist").open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleIdentifier"] == "io.github.eherrerosj.toma", info
assert info["CFBundleDisplayName"] == "Toma Personal", info
assert (
    info["TomaBuildCommit"]
    == subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
)
for language in ("en", "es"):
    assert (app / f"Contents/Resources/{language}.lproj/Localizable.strings").is_file()
architectures = subprocess.check_output(
    ["lipo", "-archs", str(app / "Contents/MacOS/Toma")], text=True
).split()
assert set(architectures) == {"arm64", "x86_64"}, architectures
signer = resolve()
verify(str(app), signer)
print(
    f"Bundle identity, build commit, localizations, both architectures and {signer.kind} signature passed."
)
