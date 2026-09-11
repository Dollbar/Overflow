# Switch service decomposition and route configuration

Read source ec31dfc is frozen and published at Overflow 283ef7d. This next increment replaces three reviewed shells with bounded local packet services. It does not implement native TL route extraction or per-hop protocol termination.

1. Independently test parameterized packet owner/round-robin arbiter, conflict-detecting data fabric, and shadow/active route table. Freeze their semantic ports before top integration.
2. Replace the three production shells; set only their inventory status to existing_partial with exact profile and reviews; regenerate role aggregates. Keep stable feature slots.
3. Refactor existing top through actual arbiter and fabric ports. Gate arbiter retirement with effective fabric valid and downstream ready. Preserve static routing by default.
4. Append ROUTE_CONFIG_ENABLE (default0) and ROUTE_INDEX_WIDTH (max1 ceil log2 PORTS) parameters and explicit route write/commit/status ports. With config enabled, table active outputs drive lookup. All new cfg outputs zero when disabled. o_route_quiescent reports reset-active no ingress valid and no arbiter packet ownership. Valid0 packet bubbles remain busy.
5. Route writes modify shadow only. Commit requires quiescence, no simultaneous write and no enabled duplicate IDs. Rejected commits preserve active and shadow. Configuration software must pause new ingress to reach quiescence; no forced mid-packet rerouting.
6. Run existing Switch packet/hold/routing fault regression on real refactored top, dynamic config checks at port1/3/4/5, unchanged full Read ESE replay, structure/elaboration and relevant tooling checks. Record source identity and bounds, then export and verify authorized remote publication.

Append top inputs: i_route_write_valid, i_route_write_index[ROUTE_INDEX_WIDTH-1:0], i_route_write_id[9:0], i_route_write_enable, i_route_commit. Append outputs: o_route_write_accepted, o_route_commit_accepted, o_route_config_pending, o_route_config_error, o_route_quiescent, o_fabric_error.

No generated candidate/build output is included in source delivery. Source tests live in verification/ip_tops, with reusable models in simulator/model if applicable. Actual hardware configuration interface is a local service contract, not a standards-defined CSR map.
