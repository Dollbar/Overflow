# Actual TL transmit buffering implementation plan

Execute inline using executing-plans and test-driven-development, independently as
requested. Existing isolated UALink branch and local ASIC tools remain selected.

Goal: replace external held fixture queues with independent actual SRAM transmit
queues ahead of the verified Request/Response selector and real credit port.
Architecture: atomic header/tag words in one FIFO per class; ordered 256-bit halves
striped across two synchronous SRAM FIFOs per class, with partial one/two-half enqueue and
one/two-half actual send acknowledgement. This supports a full Flit per cycle when
both banks are supplied and the link accepts. The existing registered SDP read
contract, exact logical counts and no same-edge freed-space borrowing are retained.
Spec: Common 2.0 §9.1 class independence, §5.1.1–5.1.2 half ordering, §5.7/§5.8
actual send and credit rules; existing tl_tx_channels_contract.json applies downstream.

Global constraints: Verilog-2001, Chinese inline RTL comments, sole i_clk with
synchronous low reset; external SRAM model explicitly supplied, never copied into
repo. Prepared headers/tags and ordered payload remain local producer interfaces;
full UPLI decode, every-VC scheduling, oversized transaction completion, full proof
and process STA remain part of the unchanged complete IP goal.

- [x] Define abstract two-half queue semantics and tests before implementation:
  partial input admission and one/two pops preserve order, invalid operations consume nothing, reset drops
  old ownership, exact full backpressure and unequal bank occupancy.
  Files model/tl/tx_data_fifo.py, verification/tl_tx_buffered/test_model.py.
  Run python3 verification/tl_tx_buffered/test_model.py; retain red and green logs.
- [x] Write real SRAM RTL scoreboard before RTL exists; cover bank depths 1,2,3,5,
  129,257, fill/drain, wrap, reset with pending read, stalls and one/two-half transfers.
  Files rtl/tl/tl_tx_data_fifo.v, verification/tl_tx_buffered/run_fifo.py.
  Run python3 verification/tl_tx_buffered/run_fifo.py --kd28-root PATH.
  Exact deque order/occupancy checks reject swapped banks, incorrect parity and
  speculative frees. Invalid requests must raise local diagnostics without pops.
- [x] Integrate tl_tx_buffered with two 512-bit header/tag FIFOs and two striped
  Data/BE FIFOs, preserving actual wire acknowledgement routing. Input producers
  keep unaccepted entries stable; tags are accepted atomically with their header.
  Files rtl/tl/tl_tx_buffered.v and verification/tl_tx_buffered/run_peers.py.
  Run three traffic modes (normal, blocked Request, blocked Response), WIDTH8/16,
  Auth0/1, Shared0/1, delay1/3; apply bounded producer gaps and small Tx depths.
  Observe producer acceptance, FIFO occupancy and actual source acknowledgements.
- [x] Independently audit actual wire, SRAM retirement, credit and queued source
  conservation; lint, generic synthesis/clock review, real mutation runs and skill
  artifact/global selftest gates. Preserve actual failures and denominators.
- [x] Update contract/review/status/checkpoint with actual results and explicit
  limitations; verify clean export, clean terminal bytecode, hash evidence and
  commit locally. No additional publication is authorized by this continuation.

Outputs: build/verification/tl_tx_buffered. Next: per-VC and capacity-aware UPLI
transaction handling, complete reference/resource induction and process STA.

Design correction from actual minimum-capacity failure: atomic pair input with total
capacity two can deadlock at occupancy one when output needs two. The final producer
contract uses o_write_taken / o_data_accepted: an offered pair may accept only its
first half. The remaining half stays upstream in order. Capacity is unchanged.
Nonzero tag fixtures use only the low used slot; all unused slots stay zero per §5.1.1.
