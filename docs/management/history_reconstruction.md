# Git History Reconstruction Plan

Status: `RECONSTRUCTED_AND_VERIFIED`

This plan records an owner-directed correction of authorship metadata. The existing repository history was
integrated and pushed by `刘键宇`, while source contributions were delivered separately by the contributors
listed in `config/contributors.yaml`. The owner confirmed that the contributors transferred the relevant
copyrights in writing to `刘键宇`, and that every listed email is linked to the corresponding GitHub account
and may remain permanently visible in Git history.

The reconstruction must not be represented as original Git capture. Author dates are reconstructed from
the owner-confirmed development periods; committer identity and integration order represent the centralized
integration performed by `刘键宇`. Commit messages created solely by the reconstruction use the word
`reconstructed`.

## Responsibility Mapping

| Primary contributor | Primary paths or change classes | Required co-authors |
| --- | --- | --- |
| 刘键宇 | architecture/configuration, NPU common/Tensor/Vector/Pod, KDLink, integration tops | relevant verification or subsystem owner |
| 李赟潇 | `rtl/npu/noc/`, NoC/CDC specifications, NoC architecture | test owner for verification changes |
| 刘仁俊 | `isa/`, `specs/isa/`, ISA portions of the baseline | 王伟林 for shared ISA/compiler planning |
| 王伟林 | `compiler/`, `specs/compiler/`, `specs/abi/` | 刘仁俊 for shared ISA/compiler planning |
| 刘浩楠 | release/build scripts, root automation, dependency locks, reproducibility fixes | affected subsystem owner |
| 刘京顺 | prose documentation, governance, release records, project-file management | affected subsystem owner |
| 秦天一 | `rtl/npu/dma/`, DMA/HBM command and data interfaces | verification owner for DMA tests |
| 付国恒 | HBM/SRAM behavioral models and timing views | 伍富; test owner where applicable |
| 伍富 | HBM/SRAM behavioral models and timing views | 付国恒; test owner where applicable |
| 陈宏伟 | reusable VIP, packages, protocol checkers, unit tests | corresponding design owner |
| 刘婉晴 | subsystem tests, CDC, bounded formal verification | corresponding design owner |
| 苏蒙 | system integration, stress, and coverage closure | corresponding design owner |

ISA and compiler directories in the 1.0 release contain specifications and ownership placeholders, not a
complete compiler implementation. Reconstruction may credit the existing specification/framework work but
must not create a commit claiming implementation that is absent from the released tree. The owner selected
this bounded attribution for 1.0 rather than waiting for future implementation files.

## Existing-History Preservation Audit

The current history contains 43 non-merge commits and 16 merge commits. All 43 non-merge patches are in
scope for preservation. A `git show --remerge-diff` audit found that 15 merge commits contain no unique
resolution patch and may be omitted when the graph is flattened. Merge `f1ecfc4f639f` (`merge: integrate
HBM and SerDes library baseline`) contains a material resolution affecting HBM/KDLink RTL, models, tests,
and interface documentation. Its resolution patch must be preserved as one explicit linear commit with a
`reconstructed(integration)` subject. Thus the reconstructed baseline contains 44 preserved historical
patch units before the separately reviewed 1.0 working-tree commits are appended.

The exact source SHA, primary author, and material co-author mapping is recorded in
`config/history_reconstruction.yaml`. The material merge-resolution unit uses `刘键宇` as primary author
and credits the HBM/SRAM, reusable VIP, subsystem verification, system verification, and documentation
owners whose work is present in the resolution patch.

## Rewrite Rules

1. Replace the existing merge graph with a linear history. Preserve the material patches from non-merge
   commits in dependency order, and add an explicitly labeled reconstruction commit only if a historical
   merge contains conflict-resolution content that is not present in either parent.
2. Use the responsible contributor as `Author`; use `刘键宇 <liujianyu20021122@gmail.com>` as `Committer`.
3. Distribute reconstructed author dates monotonically within each contributor's confirmed development
   period. Use the owner-approved `+08:00` schedule in `config/history_reconstruction.yaml`; committer dates
   are strictly increasing in the flattened integration order.
4. Add `Co-authored-by` only when the commit contains a material cross-responsibility contribution. Do not
   use trailers merely to equalize contribution counts.
5. Split uncommitted 1.0 work into the five reviewed content commits recorded in
   `config/history_reconstruction.yaml`. The fifth content commit is the immutable payload; after its fresh
   regression, append one attestation-only commit that changes only `config/release.yaml` and
   `docs/releases/ACCEPTANCE.json`.
6. The final reconstructed tree, excluding explicitly reviewed attribution/license/release metadata, must
   be byte-identical to the reviewed payload tree.
7. Run repository, release, RTL, formal, simulation, timing, and coverage gates from a fresh worktree at the
   reconstructed payload before any remote update.

## Remote Update Record and Safety

The owner selected `github/main` as the replacement target, declined creation of a remote backup branch,
and selected a flattened linear history. The replacement and later owner-approved contributor-identity
corrections use an exact fetched lease before updating the remote. Future history corrections must
continue to use `git push --force-with-lease=<expected-old-sha>`; a blind force update is prohibited.

## Reconstruction Result

The reconstructed baseline contains 44 linear historical patch units followed by five reviewed release
content commits and one attestation-only commit. Author, committer, reconstructed date, contributor identity,
and co-author trailer checks pass for the complete history. The exact old-to-rewritten mapping is recorded
in `history_reconstruction_map.tsv`; the published `main` and annotated `v1.0.0` tag use this verified
history. The reconstruction remains explicitly disclosed and is not represented as original Git capture.
