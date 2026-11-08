#!/usr/bin/env python3
"""Resolve the repository's pinned signer before changing build artifacts."""

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass

BUNDLE_ID = "io.github.eherrerosj.toma"


def run(*args, input=None):
    return subprocess.run(
        args, input=input, text=True, capture_output=True, check=True, timeout=60
    ).stdout


def config(key):
    result = subprocess.run(
        ["git", "config", "--local", "--get", key],
        text=True,
        capture_output=True,
        timeout=10,
    )
    if result.returncode not in (0, 1):
        raise ValueError(
            "Cannot read repository signing configuration; refusing an ad hoc fallback."
        )
    return result.stdout.strip() if result.returncode == 0 else ""


@dataclass(frozen=True)
class Signer:
    identity: str
    team: str
    kind: str

    def words(self):
        return f"{self.identity} {self.team} {self.kind}"


def find_signer(identity, team):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError(
            "Set a ten-character SIGNING_TEAM matching the certificate team."
        )
    listing = run("security", "find-identity", "-v", "-p", "codesigning")
    identities = re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"', listing, re.M)
    matches = [
        (fingerprint.upper(), name)
        for fingerprint, name in identities
        if identity.upper() == fingerprint.upper() or identity == name
    ]
    if not matches:
        raise ValueError(
            "The selected signing identity is unavailable. Restore it or explicitly configure another signer."
        )
    if len(matches) != 1:
        raise ValueError(
            "The signing name is ambiguous. Select its certificate SHA-1 fingerprint."
        )
    fingerprint, name = matches[0]
    if name.startswith("Developer ID Application:"):
        kind = "developer-id"
    elif name.startswith("Apple Development:"):
        kind = "development"
    else:
        raise ValueError(
            "Use an Apple Development or Developer ID Application certificate."
        )
    certificates = run("security", "find-certificate", "-a", "-c", name, "-p")
    for pem in re.findall(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", certificates, re.S
    ):
        info = run(
            "openssl",
            "x509",
            "-noout",
            "-fingerprint",
            "-sha1",
            "-subject",
            "-nameopt",
            "RFC2253",
            input=pem,
        )
        digest = re.search(r"Fingerprint=([A-Fa-f0-9:]+)", info)
        if not digest or digest[1].replace(":", "").upper() != fingerprint:
            continue
        subject_team = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", info, re.M)
        if not subject_team or subject_team[1] != team:
            raise ValueError("The signing certificate belongs to a different team.")
        return Signer(fingerprint, team, kind)
    raise ValueError(
        "The selected identity has no matching public certificate in the Keychain."
    )


def resolve():
    mode = os.environ.get("SIGNING_MODE", "auto")
    if mode not in ("auto", "stable", "adhoc"):
        raise ValueError("SIGNING_MODE must be auto, stable, or adhoc.")
    pinned = config("toma.signingIdentity")
    identity = os.environ.get("SIGNING_IDENTITY") or pinned
    team = os.environ.get("SIGNING_TEAM") or config("toma.signingTeam")
    required = os.environ.get("REQUIRE_NOTARIZATION") == "1"
    if mode == "adhoc":
        signer = Signer("-", "-", "adhoc")
    elif identity == "-":
        raise ValueError("Use SIGNING_MODE=adhoc for an explicit ad hoc smoke build.")
    elif identity:
        signer = find_signer(identity, team)
    elif mode == "stable":
        raise ValueError(
            "No stable signer is configured. Run scripts/signing.py configure first."
        )
    else:
        signer = Signer("-", "-", "adhoc")
    if required and signer.kind != "developer-id":
        raise ValueError(
            "Notarization requires a Developer ID Application certificate; "
            "development and ad hoc builds cannot be released."
        )
    return signer


def verify(app, signer):
    command = ["codesign", "--verify", "--deep", "--strict", "--all-architectures"]
    if signer.kind != "adhoc":
        if signer.kind == "development":
            issuer, leaf = "1.2.840.113635.100.6.2.1", "1.2.840.113635.100.6.1.12"
        else:
            issuer, leaf = "1.2.840.113635.100.6.2.6", "1.2.840.113635.100.6.1.13"
        rule = (
            f'anchor apple generic and identifier "{BUNDLE_ID}" '
            f'and certificate leaf[subject.OU] = "{signer.team}" '
            f"and certificate 1[field.{issuer}] exists and certificate leaf[field.{leaf}] exists"
        )
        command += ["-R", "=" + rule]
    run(*command, app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser(
        "configure",
        help="Pin one explicit identity and team in local Git configuration.",
    )
    setup.add_argument(
        "--identity",
        required=True,
        help="Certificate SHA-1 fingerprint, or an unambiguous exact name.",
    )
    setup.add_argument("--team", required=True)
    commands.add_parser(
        "resolve", help="Print validated identity, team and kind for build scripts."
    )
    check = commands.add_parser(
        "verify",
        help="Verify the app against the configured signer class, team and bundle ID.",
    )
    check.add_argument("app")
    args = parser.parse_args()
    if args.command == "configure":
        signer = find_signer(args.identity, args.team)
        run("git", "config", "--local", "toma.signingIdentity", signer.identity)
        run("git", "config", "--local", "toma.signingTeam", signer.team)
        print(f"Pinned {signer.kind} signer {signer.identity} for team {signer.team}.")
    elif args.command == "resolve":
        print(resolve().words())
    else:
        signer = resolve()
        verify(args.app, signer)
        print(f"Verified {signer.kind} signature, bundle identity and team.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.SubprocessError, OSError) as error:
        message = (
            (error.stderr.strip() or str(error))
            if isinstance(error, subprocess.CalledProcessError)
            else str(error)
        )
        print(f"Signing error: {message}", file=sys.stderr)
        sys.exit(1)
