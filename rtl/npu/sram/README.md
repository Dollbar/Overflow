# NPU Scratchpad RTL

Owns tile-private scratchpad banking and pod-shared scratchpad integration. The P0 sizing proposes 8 MiB
private SRAM per tile and 16 MiB shared SRAM per pod. Storage is explicit, software-managed, and non-coherent.

NPU-SRM-001 may study 32 banks x 256 bits and a 512 B/cycle read plus 256 B/cycle write service target.
Client request fields, ECC responses, arbitration, and reset behavior remain `HOLD` until specified.
Acceptance includes bank-conflict, simultaneous-client, ECC injection, backpressure, and starvation tests.
