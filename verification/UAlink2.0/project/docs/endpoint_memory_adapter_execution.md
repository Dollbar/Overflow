# Endpoint memory adapter execution boundary

`endpoint_memory_adapter` replaces stable Endpoint slot E:15 with a bounded one-outstanding backend lifecycle. It atomically captures the complete request-context issue tuple, holds it through backend command backpressure, accepts only the matching result after the command handshake, holds the complete 2048-bit result through formatter backpressure, then waits for an explicit matching final-response retirement before presenting the context release token. Backend command acceptance, result delivery, response retirement and context release are separate handshakes.

The adapter consumes and diagnoses early, duplicate or token-mismatched backend results and final-retirement events without changing the valid transaction. Synchronous reset cancels its local lifecycle without fabricating a release. The token is local context identity and does not overwrite any native network Tag stored inside the 184-bit payload. This partial implementation does not execute memory operations, format a response, generate a dummy completion, provide a multi-outstanding backend, or define a LinkDown recovery epoch.

Production verification:

```sh
python3 verification/endpoint_transaction/run_memory_adapter.py --label memory_adapter_prod --faults --static
```

The self-checking test separates every ownership transition, holds both command and result outputs under backpressure, rejects early and mismatched events, and checks reset cancellation. Eight source mutations cover command identity and payload truncation, completion status/data corruption, early release, completion-as-release and reset ownership. Verilog-2001 elaboration, strict Verilator lint, Yosys process/optimization/check and illegal token-width elaboration guards are part of the runner. Outputs are written below `build/verification/endpoint_transaction/memory_adapter/LABEL/`.
