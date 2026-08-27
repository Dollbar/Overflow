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
| `route_pair_order` | A following data packet cannot enter a hop before the matching Route Context ACK |
| `spine_escape` | Four-domain and eight-domain deterministic VC0 routes move only from spine input to one leaf-down egress while decrementing the domain hop limit |
| `global_commit_exact_once` | Back-to-back duplicate commits are acknowledged once each but delivered once, same-slot identity collisions remain blocked through the replay grace interval, and route soft reset preserves history |
| `route_stage_scale` | Every symbolic 8-bit destination selects exactly one top, middle, and leaf radix-8 egress with monotonic hop decrement |
| `hierarchical_membership` | Hierarchical phases never regress and inter-domain commands target only a non-local group member |
| `scale_route_control` | Every symbolic 15-bit destination decomposes into the five radix-8 egress digits, stage metadata spans ranks one through five, and adaptive traffic can enter but never leave the monotonic escape order |
| `card_directory` | A non-quiescent card-directory commit preserves the complete old map, while a quiescent commit atomically publishes the new epoch, ownership, card profile, and health-qualified node state |
| `coverage_reachability` | Defensive FSM encodings remain unreachable and binary FP32 addition cannot select the minimum-normal promotion guard after reset |

The leaf-domain escape proof matches the frozen reference topology: a switch-plane route is a single direct
ingress-to-destination-egress transfer. The multidomain proof adds the structural
`leaf-up -> spine -> leaf-down` ordering for every destination in the four-domain and eight-domain profiles.
The spine has no leaf-down-to-spine transition, so deterministic VC0 cannot form a cyclic wait dependency
within these profiles. The schema-3 `route_stage_scale` proof extends that deterministic dependency order
through one to three radix-8 stages for up to 256 domains. The schema-4 `scale_route_control` proof covers
all five digits of the 15-bit destination-domain field, the rank-one-to-rank-five boundary, and the one-way
adaptive-to-escape transition used for up to 32,768 leaf domains. These are proofs of the implemented radix-8
route contracts, not arbitrary user-defined cyclic topologies.

These bounded proofs complement, rather than replace, the long randomized and directed RTL simulations.
