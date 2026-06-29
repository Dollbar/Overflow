# NPU Pod-to-NoC Clock-Domain Crossing

Status: implementation baseline for a Pod clock distinct from the Router clock.

## 1. Scope

The Pod attachment is synchronous to its Pod clock. The Router is synchronous to the NoC clock. When the
clocks differ, every ready/valid lane crosses through one Gray-pointer asynchronous FIFO. No payload bit,
valid flag, credit pulse, or reset release is synchronized independently.

The proposed logical profile uses a 1 GHz Pod clock and a 2 GHz NoC clock. These are verification ratios,
not physical frequency evidence. The wrapper must also operate with unrelated phase and small rational or
irrational simulation ratios.

## 2. FIFO Mapping

| Direction | Channel | Count per Pod | Logical depth |
| --- | --- | ---: | ---: |
| Pod to NoC | Control | 1 | 8 |
| NoC to Pod | Control | 1 | 8 |
| Pod to NoC | Data | 2 | 16 per lane |
| NoC to Pod | Data | 2 | 16 per lane |

Packed control flits are padded from 158 to 160 bits inside the FIFO. Packed data flits are padded from
1,166 to 1,176 bits. Padding is written as zero and ignored after readout. The external flit contract is
unchanged.

## 3. Reset and Quiesce

Both domains participate in the same FIFO reset event. Reset assertion may be asynchronous; deassertion is
synchronized independently in each domain before reaching FIFO control. One-sided runtime reset is not
supported because it invalidates Gray-pointer ownership.

Quiesce is initiated in the Pod domain. The Pod attachment first blocks new SOP admission and drains packet
tails. The transmit CDC FIFO then drains into the Router. Router and receive FIFOs drain before system-level
quiesced state is reported. Reset is not a substitute for lossless quiesce.

## 4. Verification Obligations

CDC verification includes 1:1, 1:2, 2:1, phase-swept, and unrelated-period clocks; simultaneous full/empty
turnover; output backpressure; wraparound; reset assertion from either phase; synchronized release; packet
metadata stability; no loss, duplication, or reordering; and complete quiesce drain. Structural CDC review
must identify only Gray-pointer synchronizers as multi-bit control crossings.
