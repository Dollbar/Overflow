# KDLink CDC Audit

KDLink uses explicit clock-domain partitions:

- tensor/descriptor interfaces are in the NPU core clock domain;
- reliable forward and reverse link state is in the link PHY clock domain;
- `coll_async_fifo` carries multi-bit streams and uses Gray-coded pointers with two destination-domain
  synchronizer stages;
- `coll_toggle_handshake` carries isolated control pulses;
- `coll_reset_sync` may be used where a system provides asynchronous assertion and requires synchronous
  deassertion.

Run the structural audit from the repository root:

```bash
python3 verification/kdlink/scripts/run_static.py
```

The current RTL interfaces accept a reset input for each declared domain. Integration must assert resets
for both sides of an asynchronous FIFO together and must synchronously deassert each domain reset. The
portable RTL does not contain an analog PLL/CDR reset sequencer and does not claim RDC signoff for a final
SoC reset tree.
