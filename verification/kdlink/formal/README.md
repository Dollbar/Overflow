# KDLink Formal Properties

Run the bounded formal gate from the repository root:

```bash
python3 verification/kdlink/scripts/run_formal.py
```

The release properties are deliberately partitioned so that each proof has a clear contract and bounded
state space:

| Proof | Contract |
| --- | --- |
| `fifo_credit` | FIFO occupancy safety, no overflow/underflow, credit conservation and admission |
| `rx_exact_once` | Atomic single commit, retry duplicate suppression, and ACK of original plus retry |
| `replay_progress` | Timeout replay is emitted on VC6, data is retained, and ACK releases the slot |
| `vc_service` | SOP-to-EOP ownership, 16-flit packet bound, and bounded management/replay service |
| `escape_dependency` | Exhaustive 32-node direct VC0 route dependencies have no intermediate channel edge |

The escape proof matches the frozen reference topology: a switch-plane route is a single direct ingress to
destination-egress transfer. VC0 therefore introduces no channel-to-channel dependency edge and cannot form
a cyclic wait graph inside the reference fabric. This is not a proof for arbitrary multi-hop topologies.

These bounded proofs complement, rather than replace, the long randomized and directed RTL simulations.
