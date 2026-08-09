# Security Policy

## Supported Versions

After the 1.0 release is published, the latest tagged release and the current default branch receive
security corrections. Unreleased historical candidates and development branches are not supported
products.

## Reporting a Vulnerability

Do not disclose a suspected vulnerability, exploit, credential, or restricted artifact in a public issue
or pull request. Use the repository's private vulnerability-reporting form under GitHub Security Advisories.
If that feature is unavailable, contact the maintainers privately through the repository owner's verified
GitHub profile and provide only enough public information to establish a private channel.

Include the affected commit or tag, configuration, threat model, reproduction steps, impact, and any
suggested mitigation. Maintainers will acknowledge when the report is received, assess whether it is in
scope, coordinate a correction and disclosure when appropriate, and credit the reporter if requested.
Response dates depend on maintainer availability and are not a contractual service-level agreement.

Security-sensitive scope includes RTL privilege or isolation failures, malformed-command handling,
DMA address or length enforcement, NoC/KDLink packet validation, replay or duplicate-commit behavior,
dependency and release-script compromise, and accidental publication of credentials or restricted inputs.
Physical attacks, analog PHY behavior, vendor silicon errata, and systems not represented by the released
source may require coordination with their respective owners.

## Release Integrity

Only annotated release tags that pass the process in `docs/management/release_management.md` are formal
releases. A branch, archive, or candidate marked `HOLD` is not a security-supported release.
