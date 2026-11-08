Configured local builds reuse one Apple signing identity, so rebuilds keep a compatible macOS privacy identity.

Ad hoc signatures changed with each binary and repeatedly invalidated Screen Recording permission. The signing setup now pins an explicit certificate fingerprint and team in repository-local Git configuration. Missing certificates, ambiguous names, team mismatches and configuration errors stop the build before compilation or replacement of the previous output.

The approved local signer is an Apple Development certificate. Each signed app must pass Apple trust, certificate-class, team and bundle-identifier checks. macOS generates its designated requirement. The implementation does not replace or weaken it. CI uses an explicit ad hoc mode for disposable smoke builds. Release preflight rejects development and ad hoc certificates and still requires Developer ID notarization.

Validation passes 14 signing/release tests and 41 Swift tests. Real signing probes produced different executables with identical, mutually compatible designated requirements. An ad hoc replacement failed the same requirement. Python lint, formatting, security checks and shell syntax checks pass.

Version 1.4.1 changes the installed app from ad hoc to development signing. That transition requires granting Screen Recording again. Switching later to Developer ID can require another grant. Public notarized distribution remains unavailable without a Developer ID Application certificate and notary credentials.
