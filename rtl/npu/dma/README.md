# NPU DMA Front End

Owns the NPU-side descriptor scheduler, address generation, scratchpad mover, coalescing requests, QoS tags,
and data credits. `rtl/memory/` owns the abstract HBM transaction machinery and external-memory behavior.
The boundary between these directories must be versioned in `specs/interfaces/`.

The P0 proposal provisions one engine per pod, 16 logical channels, 64 active descriptors, and 4096 x
128-byte in-flight data beats. At 625 GB/s this 512 KiB window covers the declared 800 ns stress latency
(`ANALYTICAL`). Descriptor/address widths, ordering, cancellation, protection, and errors remain `HOLD`.
Acceptance requires stride, gather/scatter, alignment, backpressure, fault, QoS, and saturation RTL tests.
