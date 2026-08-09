# Overflow Release Notes

## Overflow 1.0.0

- Prepared: 2026-08-31
- Published: 2026-09-01
- Tag: `v1.0.0`
- Publication status: `GO`

This release is the first formal source-and-verification baseline for the complete repository-owned
model-to-synthesizable-RTL boundary. It integrates the MX compute path, independent Vector issue,
decoded-command gateway, DMA, 16 MiB Pod-shared SRAM, complete two-cluster compute Pod, managed eight-Pod
array, three-plane 2 by 4 NoC with per-Pod CDC, and the joint production Pod/NoC top. It also retains the
KDLink endpoint/router/collective and digital SerDes package, HBM behavior, KD28 SRAM/FIFO models, reusable
VIP, and their layered verification assets.

The release is deliberately bounded. It does not claim a complete compiler/runtime/driver product,
execution of Kimi-K3 weights, end-to-end 50 token/s performance, measured 2 PFLOPS or 5 TB/s silicon,
frozen production private SRAM capacity, analog PHY compliance, or physical implementation signoff.
Fourteen `PROPOSED` requirements are enumerated as explicit non-claims in `config/release.yaml`.

Measured code-coverage thresholds are enforced for KDLink, the Pod array, and NoC. Compute, decoded-command,
and NPU-system closure use extensive directed and stress simulation, lint, and synthesis-readiness checks,
but do not produce a single merged release-gated code-coverage number. This release therefore makes no
claim of exhaustive repository code or functional coverage.

The complete portable suite passed in the isolated release worktree after stable-file normalization. This
includes HBM, KD28 memories, interface timing, KDLink, NPU-owned RTL, Pod, NoC, and joint Pod/NoC gates.
The later owner-directed contributor-identity corrections changed commit metadata and attribution/release
documents only; production RTL, verification sources, models, interfaces, and build scripts remain
byte-identical to the regression-passed payload. Repository and strict release audits were repeated after
each metadata correction. `docs/releases/ACCEPTANCE.json` is authoritative.

Current integrated results include all 64 control routes and 512 data lane/VC routes across eight distinct
Pod clock domains. NoC full-suite coverage passed at line 93.3%, branch 79.4%, expression 63.0%, and toggle
40.8%; Pod-array coverage passed its separate declared thresholds. These are thresholded RTL metrics, not
an exhaustive functional-coverage or silicon-signoff claim.

Reproduce the release with:

```bash
python3 -m pip install --require-hashes -r requirements-build.lock
python3 -m pip install --require-hashes --no-build-isolation -r requirements-dev.lock
make release-preflight
make release-audit
make release-regression RELEASE_JOBS=2
make release-check
```

Expected terminal signatures are `RELEASE_REGRESSION_PASS` after the portable suite and
`RELEASE_GATE_PASS` with zero errors and zero holds for the strict publication audit.

The sections below retain earlier KDLink and repository-candidate history. Their historical branch and PR
states are not the current overall 1.0 publication decision.

## KDLink v0.4 million-scale release candidate

- Prepared: 2026-08-27
- State: `MERGED_BY_PR_20`
- Release relationship: PR #20 was incorporated into the published Overflow 1.0 baseline
- Candidate base: `origin/main` at `ac71fe8fca39130c6b0e22bc44ea3106c3175af8`
- Development isolation: `feat/kdlink-million-scale`
- Inherited branch head: `4bd201f54e7b1fa133b56af01be776432f57918e`, containing the rebased previously
  committed KDLink v0.3 base

This candidate extends KDLink without renaming engineering sources or changing the released schema-2 and
schema-3 formats. Schema 4 provides 20-bit endpoint addressing, 15-bit leaf-domain identifiers, and up to
five radix-8 inter-domain stages. The compositional architecture accepts every active population from one
through 1,048,576 NPU endpoints across up to 32,768 32-NPU leaf domains. A leaf may use homogeneous or mixed
physical card profiles containing 1, 2, 4, 8, 16, or 32 NPUs per card; card packing does not alter global
routing. Directed irregular-population coverage includes 2, 3, 33, 78, and 15,132 endpoints plus adjacent
leaf, radix, and maximum-population boundaries.

The implementation adds bounded five-stage route selection, distributed group-directory and tree control,
route-epoch and plane selection, deadlock guarding, a card directory with atomic reconfiguration, and
pipelineable source transaction and destination commit windows. Analytical per-tier bandwidth planning and
a compressed cluster-inference simulator cover leaf plus five hierarchy tiers, independently keyed group,
plane, and direction resources, shared physical VC capacity, TP/EP/PP/DP traffic, overload, throughput, and
deterministic serving-tail metrics. These performance inputs and rates remain explicitly analytical rather
than measured.

The repository-owned verification package and reusable stream VIP now cover the complete supported wire
format set. Schema-2 baseline traffic, schema-3 and schema-4 Route Context, schema-2 and schema-4 Global
Commit, explicit capability rejection, control-payload reserved fields, CRC corruption, valid/ready
backpressure, packet ownership, multi-flit sequence, declared Route Context packet length, and recovery
after a malformed sequence are self-checked. The environment package exhaustively round-trips the frozen
512-slice legacy endpoint map and all six supported card-profile codes; the serial-interface test preserves
the vendor-neutral digital SerDes boundary. These are verification-only additions and do not change the
production wire encoding or RTL datapath.

Executed release evidence:

| Gate | Command | Result |
| --- | --- | --- |
| Portable release suite | `make kdlink-release-check` | preflight, 216/216 model tests, 61/61 RTL tests, 27 lint tops, 7 CDC contracts, 13/13 bounded formal proofs, coverage, and repository consistency PASS |
| RTL coverage | `python3 verification/kdlink/scripts/run_coverage.py --jobs 4` | cold 48/48 tests and 15/15 critical modules PASS; line 100.0%, toggle 95.3%, branch 95.7%, expression 93.1% |
| Multi-corner partition STA | `python3 verification/kdlink/scripts/run_sta.py` with the recorded 1.000 ns constraint and three external libraries | 72/72 partition-corners and all three synthetic interface views PASS |
| Reusable package and VIP | `python3 simulator/kdlink/scripts/run.py --test env_pkg`, `--test vip_stream`, and `--test serial_if` | schema 2/3/4 codecs, capability gates, CRC, control payloads, packet sequence/pairing, all card codes, exhaustive legacy endpoint mapping, and typed serial boundary PASS |
| Hierarchy bandwidth plans | `report_bandwidth.py 1048576 --profile nonblocking` and `--profile balanced` | 32,768 leaves, five active route tiers, and declared one-link-equivalent failure headroom at every tier PASS; `FUNCTIONAL_SIM` with `ANALYTICAL` inputs |
| Cluster inference scenarios | `run_cluster_inference.py` with dense, MoE, failure, and serving configs | million-endpoint dense and MoE, irregular 15,132-endpoint failure, plus 16-request FCFS serving latency/queue/throughput reports PASS; `FUNCTIONAL_SIM` with `ANALYTICAL` inputs |

The STA run maps 24 registered partitions independently at fast, typical, and slow TSMC28 corners. It uses
a 1.000 ns clock, 0.100 ns setup uncertainty, 0.020 ns hold uncertainty, and a 0.100 ns mapping target. The
minimum setup slack is +0.0020 ns at the slow `coll_reduction_engine`; the minimum hold slack is +0.0098 ns
at the fast `coll_reduction_engine`. Library labels and SHA-256 digests, but no host paths or proprietary
library contents, are recorded in `KDLINK_ACCEPTANCE.json` and the STA summary.

This is RTL release-candidate engineering signoff. Million-scale support is a compositional address,
routing, directory, functional-traffic, and analytical-capacity claim; it does not instantiate one million
RTL endpoints. The STA evidence is mapped-cell and pre-layout. Analog SerDes, HBM PHY, vendor macro timing,
clock-tree and extracted-parasitic timing, package/PCB analysis, place-and-route, hardware interoperability,
and tapeout signoff remain outside this result. SerDes behavioral-model sources and HBM/SerDes Liberty
sources are unchanged from `origin/main` and are not part of this candidate delta.

The machine-readable acceptance result is `docs/releases/KDLINK_ACCEPTANCE.json`. The v0.4 branch is pushed
and PR #20 is merged in the current `main` history; it is not independently tagged. The exact final-tree candidate relative
to `origin/main` intentionally also includes the inherited v0.3 branch commits.

## KDLink v0.3 multidomain release candidate

- Prepared: 2026-08-24
- State: `PUSHED_AS_DRAFT_PR`
- Review gate: draft PR #17 is open; user approval is required before merge or release tagging
- Candidate base: `origin/main` at `f7c825d`
- Development isolation: `feat/kdlink-multidomain` in its dedicated worktree

This candidate adds the complete KDLink multidomain increment while preserving the existing schema-2
32-node leaf domain. Hierarchical traffic uses schema 3 and stable, version-neutral engineering filenames.
The implementation covers 2, 4, 8, 16, 32, 64, 128, and 256 domains, up to 8,192 globally addressed
leaf endpoints.

The architecture and implementation are frozen as KDLink v0.3. Review may change documentation or correct
a release-blocking defect, but feature additions, field-width changes, larger topology limits, or filename
versioning require a separate post-v0.3 development scope and renewed verification.

Included scope:

- Route Context encode, validation, context-before-data ACK ordering, packet lock, and hop-local replay.
- Fixed radix-8 routing through one, two, or three inter-domain stages with failed-egress masking.
- Sixteen source replay slots and sixteen destination commit-history slots for end-to-end transaction
  retention, lost-ACK replay, route-reset recovery, replay-grace collision protection, and destination
  duplicate suppression. A schema-2 message-type-9 commit packet closes the transaction over the existing
  reliable endpoint, PCS, and SerDes transport.
- Four 256-domain group-table entries and explicit leaf/inter-domain/completion control for ReduceScatter,
  AllGather, AllReduce, AllToAll, AllToAllv, and point-to-point.
- Backward-compatible reliable-endpoint handling for schema-3 Route Context and schema-2 global-commit
  extension packets, disabled by default on baseline instances.
- Repository-rooted toolchain manifest, path/dependency audit, and unified Make targets for every portable
  KDLink release gate; licensed standard-cell STA remains a separate explicit external-input gate.

Tools used: Verilator 5.050 (2026-07-24 build), Python 3.12.3, pytest 9.1.1, Yosys 0.67+post
(`b8e7da6f40ae8f552c116bf6c359b07c6533e159`), and OpenSTA 3.1.0.

Executed gates:

| Gate | Command | Result |
| --- | --- | --- |
| Release environment preflight | `make kdlink-preflight` | 54 manifest paths, repository dependencies, stable filenames, host-path hygiene, and open-tool minimum versions PASS from repository and external working directories |
| Functional model | `python3 simulator/kdlink/scripts/run.py --model` | 68/68 PASS |
| RTL regression | `python3 simulator/kdlink/scripts/run.py --group all --jobs 4` | 54/54 PASS |
| Lint and CDC | `python3 verification/kdlink/scripts/run_static.py` | 15 lint tops and 7 CDC contracts PASS |
| Formal | `python3 verification/kdlink/scripts/run_formal.py` | 10/10 bounded proofs PASS |
| Coverage gate | full cold acquisition of all 42 coverage tests | line 96.0%, toggle 95.4%, branch 94.8%, expression 93.6%; all six critical-module gates PASS |
| Multi-corner STA | `python3 verification/kdlink/scripts/run_sta.py --period-ns 1.000 --corner fast=<external.lib> --corner typical=<external.lib> --corner slow=<external.lib> --driving-cell BUFFD4BWP40P140` | 51/51 corner-partitions PASS |

The coverage report unions source points across parameterized hierarchies. All 42 raw databases were freshly
acquired in the final cold release run. Per-module gates require line 90%, branch 80%, and toggle 80% for the
route stage, global source, global tracker, global commit codec, group table, and hierarchical controller;
a metric with no instrumentable points is treated as not applicable. Generated databases and work
directories are excluded from the candidate.

The STA run independently maps 17 registered partitions at fast, typical, and slow TSMC28 corners. Each
corner also loads its matching repository HBM/SerDes interface Liberty view. External TSMC28 standard-cell
libraries are local dependencies and are not distributed. The minimum setup slack is +0.1168 ns at the
slow `kdlink_global_commit_tracker`; the minimum hold slack is +0.0098 ns at the fast
`coll_reduction_engine` corner. This is pre-layout
cell-delay evidence, not a flat fabric, placed-and-routed, analog SerDes, package, PCB, or hardware timing
claim.

The repository-provided SerDes behavioral models are used by joint PCS/link regression but are unchanged
from `origin/main` and excluded from this candidate; only their README's obsolete manifest count is corrected.
The NPU implementation and every HBM/SerDes model or Liberty source remain untouched. A hard reset that destroys both global transaction tables starts a new
protocol session; exact-once continuity across independent power loss requires a higher-level persistent
session mechanism and is outside this increment.

## v0.1 release candidate

- Prepared: 2026-08-21
- State: `PREPARED_NOT_PUBLISHED`
- Review gate: user approval is required before staging, committing, tagging, or pushing
- Candidate base: `origin/main` at `579cab4`
- KDLink external-model source: upstream commit `8205f04`
- HBM/SerDes interface-Liberty source: upstream commit `a2853a2`

This candidate packages the current repository baseline as the overall Overflow `v0.1` release. Source,
testbench, model-interface, script, configuration, requirement, and traceability filenames are stable and
contain no release or protocol version suffix. `KDL_SCHEMA_VERSION = 2` is the frozen KDLink on-wire schema
value; it is intentionally independent of the product release label.

## Included KDLink scope

- 640-bit forward flit, 512-bit payload, 128-bit reverse control, eight VCs, and 16-flit packets.
- Autonomous initialization, cumulative credit, ACK/NACK, timeout replay on VC6, exact-once receive commit,
  duplicate suppression, reset and epoch recovery.
- Two-slice bonded operation, degradation, replay migration, mapping checks, and 8-plane reliable NIC
  integration.
- Eight cards, four NPUs per card, 32 nodes, eight switch planes, and 512 logical slice paths in the
  portable baseboard environment.
- Six collective/point-to-point operations, 16 concurrent contexts, and INT32/FP32/FP16/BF16 reduction.

## Verification evidence

Tools used:

- Verilator 5.050, build dated 2026-07-24
- Python 3.12.3
- pytest 9.1.1
- Yosys 0.67+post (`b8e7da6f40ae8f552c116bf6c359b07c6533e159`)
- OpenSTA 3.1.0

Executed gates:

| Gate | Command | Result |
| --- | --- | --- |
| Functional model | `python3 simulator/kdlink/scripts/run.py --model` | 26/26 PASS |
| RTL regression | `python3 simulator/kdlink/scripts/run.py --group all --jobs 2` | 41/41 PASS |
| HBM model and BFM | `make hbm-model` | 27/27 Python cases and RTL beat BFM PASS |
| Lint and CDC | `python3 verification/kdlink/scripts/run_static.py` | 6 lint tops and 7 CDC contracts PASS |
| Formal | `python3 verification/kdlink/scripts/run_formal.py` | 5/5 bounded proofs PASS |
| Coverage acquisition | `python3 verification/kdlink/scripts/run_coverage.py --jobs 2` | 29/29 instrumented tests produced valid raw databases |
| Coverage gate | `python3 verification/kdlink/scripts/run_coverage.py --reuse-existing` | PASS after corrected source-point aggregation |
| Interface STA | `make sta-interfaces` | fast, typical, and slow HBM/SerDes interface views PASS |
| Multi-corner STA | `python3 verification/kdlink/scripts/run_sta.py --period-ns 1.000 --corner fast=<external.lib> --corner typical=<external.lib> --corner slow=<external.lib> --driving-cell BUFFD4BWP40P140` | 30/30 corner-partitions pass setup and hold |

Coverage is source-level RTL coverage after unioning hierarchy and all Verilator parameterized-page
suffixes. The raw databases were generated by the complete 29-test instrumented run. After correcting a
report-only suffix canonicalization bug, the same raw databases were re-aggregated with
`--reuse-existing`; no test result or counter was synthesized.

| Metric | Result | Gate |
| --- | ---: | ---: |
| Line | 97.4% (341/350) | 95% |
| Toggle | 95.5% (48,572/50,870) | 95% |
| Branch | 96.0% (626/652) | 90% |
| Expression | 95.0% (4,572/4,814) | reported |

The 1.000 ns pre-layout cell-delay STA independently mapped all ten registered partitions against external
TSMC28 fast (`ffg1p05v/-40 C`), typical (`tt0p9v/25 C`), and slow (`ssg0p72v/125 C`) standard-cell
Liberty views, which are not distributed. Setup uncertainty was 0.100 ns and hold uncertainty was 0.020 ns.
All 30 corner-partitions passed both setup and hold. The smallest setup slack was +0.0020 ns in the slow
`coll_reduction_engine`; the smallest hold slack was +0.0098 ns in the fast `coll_reduction_engine`.

The same flow validates and runs OpenSTA on the repository-distributed fast, typical, and slow synthetic
HBM/SerDes interface Liberty views. These views establish only front-end constraint plumbing and explicit
black-box timing arcs. The combined result is not a placed-and-routed FPGA, ASIC top-level, HBM PHY, or
analog SerDes timing claim.

## SerDes boundary

SerDes simulation models are not part of this upload candidate. Joint simulations resolve the reusable
models already present on `origin/main` under `Library/models/kdlink/serdes/`; those upstream filenames and
design-unit names are retained as external dependency identifiers. No file from that directory is listed
for upload.

`simulator/kdlink/model/link/kdlink_reverse_channel_model.sv` is not a SerDes model. It is a portable,
registered 128-bit protocol-control delay/fault model used for ACK, NACK, credit, and link-management words.

## Known limitations

- The external SerDes models are deterministic digital behavioral models, not AMD/Xilinx GT hard macros,
  analog channels, CDR/equalization models, or signal-integrity evidence.
- No Vivado place-and-route, bitstream, board measurement, or hardware interoperability result is claimed.
- The baseboard test exercises all 512 logical paths and isolation controls, while reliable endpoint + PCS +
  SerDes behavior is exercised in representative E2E compositions rather than a monolithic 512-SerDes model.
- The logic STA evidence is partitioned and pre-layout; its standard-cell Liberty files are not distributed.
- The distributed HBM/SerDes interface Liberty views are synthetic and do not replace vendor macro views.
- Generated build directories, waveforms, logs, proprietary timing libraries, and SerDes model sources are
  excluded from upload.

## Publication state

No files have been staged, committed, tagged, or pushed for this candidate. The exact candidate whitelist
and exclusion list are maintained in `docs/releases/UPLOAD_MANIFEST.md` for approval.
