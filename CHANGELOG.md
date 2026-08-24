# Changelog

Significant changes are recorded under Added, Changed, Fixed, Removed, and Security.

## [Unreleased]

### Added

- Established the OwerFlow v0.1 model-to-RTL architecture baseline.
- Defined the OF-5P6T workload envelope, system context, and evidence policy.
- Added repository, risk, release, and requirement-traceability rules.
- Added the MX-only GEMM/vector v0.2 interface, numerical blocks, SRAM-boundary models, and deterministic
  RTL regressions for MXFP4 E2M1 and MXFP8 E4M3FN.
- Added self-describing MX post-result beats and 16-channel peak regressions for
  bubble-free Vector and external MX result transport.
- Added a mandatory TSMC28 HPC+ SSG 0.72 V/125 C, 1 GHz mapped-PE STA gate to
  the GEMM/vector `make test` regression.
- Added full-array buffer-to-GEMM regressions for K=256 and K=4096 continuous
  streams of 256 A and 256 B elements per cycle with complete 65,536-result
  checking.

### Changed

- Froze the repository lower boundary at synthesizable RTL and behavioral external-interface models.
- Updated the GEMM/vector path to use 32-element MX blocks with E8M0 scales,
  direct registered west-to-east/north-to-south Tile links, paired MX feedback
  quantization, and non-transposed feedback storage.
- Unified Vector, external, and feedback output selection under the descriptor
  `output_mx_format` field and made external completion wait for final result
  consumption.
- Restored exact-product-only GEMM PEs, double-buffered each Tile's 16-cycle A/B
  blocks, and moved the reduction tree plus sixteen 85-bit long-K accumulators
  to Tile scope; added a memory-bounded full 65,536-PE Verilator regression.
- Increased each default Tensor-A, Tensor-B, Vector-B, and Vector-C data store
  to 8 MiB and moved atomic Tile-group skew behind the dense GEMM input boundary.
- Reduced the v0.2 numeric ABI to E2M1/E4M3FN with RNE-only conversion,
  removed rounding metadata from descriptors and the GEMM/Vector transport,
  and added scheduler rejection for older descriptor versions and reserved MX
  format encodings.

### Removed

- Removed implementation and project-planning domains outside the model-to-RTL boundary.
- Removed the GEMM Tile packet routers, root dispatcher, routing flits,
  programmable Tile anchor/span ABI, and 4096-cube block-matrix scheduler test.
- Removed MXFP8 E5M2 and the four-way rounding selector from the v0.2
  production MX path.
