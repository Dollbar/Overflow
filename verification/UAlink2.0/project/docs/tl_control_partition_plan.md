# Capacity-aware Control field partition implementation plan

Execute independently with writing-plans, executing-plans, test-driven-development
and erie-verilog-generator; current isolated local ASIC branch remains selected.
Goal: emit capacity-fitting prefixes of independent prepared TL fields into the actual
Tx SRAM queues, without splitting or rewriting any individual transaction.

Spec: private Common2.0 §5.1.1 field/data/tag order, §5.8 credit inheritance and stable
initial capacities, §5.9 field alignment, §2.7.8 distinction between source-selected
single-beat responses and multi-beat transfers. There is no basis here for arbitrary
Write/Atomic splitting or silently changing forwarded response mode. This stage
solves an oversized field GROUP, not an individually oversized transaction.

Architecture: retain source batch until every field is enqueued. A four-bit sector
cursor removes consumed prefixes; choose the longest remaining complete-field prefix
fitting actual initialized TOTAL physical capacity and the Auth four-tag limit. Keep
field bits at original naturally aligned sector positions, zero omitted sectors,
and shift corresponding tags to low slots. Current balances and catch budgets remain
checked later by the real transmit selector/port. Capacity/auth are stable in an epoch;
no speculative credit reservation or extra wire format is introduced.

- [x] Tests before model/RTL: grouped four single-beat Read Responses with capacity1
  become four unchanged fields in order; shared Pool uses merged slot10; Auth tag
  order and zero unused slots; invalid class/non-NOP FC and oversized first field
  retain source and report diagnostics. Model model/tl/control_partition.py and
  verification/tl_control_partition/test_model.py.
- [x] RTL rtl/tl/tl_control_partition.v: fixed eight possible boundaries from the
  actual field-start decoder, confirmed tenure check, per-prefix credit qualification,
  four-bit cursor, only real header-queue enqueue advances cursor/source completion.
  Run verification/tl_control_partition/run_rtl.py: actual model/RTL vectors include
  reset during a batch, downstream stalls and all boundary/width/Auth/shared cases.
- [x] Connect per-class partitioners before tl_tx_buffered in a real dual-port/SRAM/FC
  TB. Use low CMD/Data capacity1 groups, source data gaps and queue stalls. Preserve
  individual tags/status/offset/Last and every Data/BE half at the receiver; prove
  source acknowledgement only after all grouped fields are safely enqueued.
- [x] Audit actual field sequence, source cursor, stored tags, real wire/Rx SRAM and
  credit conservation. Run real wiring faults, lint, synthesis/clock review and skill
  gates; retain every failed and passed run with source hashes.
- [x] Clean-export compatibility, contract/review/status/checkpoint, terminal compiler
  artifact cleanup, hash manifest and local commit. Full UPLI, each-VC scheduling,
  individual oversized handling, Poison, complete proofs and process STA remain open.

Commands: python3 verification/tl_control_partition/test_model.py;
python3 verification/tl_control_partition/run_rtl.py;
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow.
Output build/verification/tl_control_partition; source is held until o_source_taken,
whereas o_taken is one actual output partition accepted by the downstream header FIFO.
