# Contributing

## Contribution Flow

1. Start from an approved issue, requirement ID, or ADR.
2. Update `specs/` and obtain interface-owner review before changing a cross-layer interface.
3. Include implementation, tests, documentation, and traceability updates in the same change.
4. Pull requests identify affected directories, compatibility, executed validation, results, and risk.
5. All required target-directory gates must pass before merge.

## Commit Messages

Use this format:

```text
<scope>: <English summary>
```

Common scopes include `model`, `compiler`, `isa`, `runtime`, `simulator`, `rtl`, `kdlink`,
`verification`, `docs`, and `ci`.

## Developer Certificate of Origin

Overflow uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/). Every external
contribution commit must contain a `Signed-off-by` trailer using the contributor's real name and a valid
email address:

```text
Signed-off-by: Full Legal Name <email@example.com>
```

Create the trailer with `git commit -s`. A sign-off certifies that the contributor has the right to submit
the contribution under the license applicable to the changed path. Maintainers must not merge commits
that lack the required sign-off.

## Interfaces and Compatibility

- Model schemas, ISA, ABI, register maps, packet formats, and digital interface contracts are versioned.
- Breaking changes require migration guidance and a corresponding major-version increase.
- A producer-side change updates its consumers and conformance tests in the same review series.

## Documentation Language

README, architecture, management, and release documentation must be written in English.
