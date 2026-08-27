# KDLink Specifications

Contains logical flits, reliable link, routing, virtual channels, congestion, switch planes, collectives,
AllToAllv, and recovery. Analog PHY implementation is external, but the digital PHY contract is complete.

- `kdlink_requirements.md` is the frozen implementation and release acceptance contract.
- `simulation_environment.md` defines the portable digital multi-board verification boundary.
- `multidomain_architecture.md` defines the isolated hierarchical extension and its evidence boundary.
- `scale_architecture.md` defines the schema-4 five-stage radix-8, distributed-state, per-tier bandwidth,
  oversubscription, failure-headroom, BDP, and compressed cluster-inference simulation contract for up to
  1,048,576 global endpoints, with 1/2/4/8/16/32-NPU physical-card packing inside each 32-node leaf.
