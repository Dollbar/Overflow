# HBM Physical Mapping Proposal

Status: `PROPOSED`, not frozen. Evidence level: `ANALYTICAL`.

## Anchored Logical Target

The accepted system baseline assigns one logical NPU 192 GB of HBM capacity and 5 TB/s of aggregate
read-plus-write payload bandwidth. The current NPU proposal divides this into eight independent logical
partitions, each with 24 GB capacity and 625 GB/s of shared read-plus-write payload bandwidth. Across the
32-logical-NPU system, the corresponding logical targets are 6.144 TB capacity and 160 TB/s aggregate
payload bandwidth.

## Proposed Physical Mapping

The current physical planning profile maps each 24 GB logical partition one-to-one onto one public
reference 24 GB, 8-high HBM3E stack. This yields the following provisional geometry:

| Quantity | Per logical NPU | 32-NPU system |
| --- | ---: | ---: |
| HBM3E stacks/packages | 8 | 256 |
| DRAM dies at 8-high per stack | 64 | 2,048 |
| Physical/reference capacity | 192 GB | 6.144 TB |
| Logical read-plus-write payload target | 5 TB/s | 160 TB/s |
| Public advertised bandwidth floor | >9.6 TB/s | >307.2 TB/s |

The model profile records a public advertised floor greater than 1.2 TB/s per stack. Eight stacks
therefore provide a reference floor greater than 9.6 TB/s per NPU. The 5 TB/s logical target consumes
less than 52.08 percent of that floor before controller, protocol, refresh, ECC, thermal, and workload
efficiency losses. This is capacity and bandwidth headroom, not sustained-system evidence.

Here, "stack" means one HBM package/stack visible to the package design. The derived DRAM-die count
assumes the selected 8-high profile and excludes base/control dies from that DRAM count.

## Freeze Gate

The one-partition-per-stack mapping is not part of ADR-0002 and is not yet an accepted package decision.
A physical/package ADR must select the HBM generation and vendor-neutral capacity class, stack count,
stack height, controller/PHY ownership, package topology, power and thermal envelope, repair policy, and
achievable controller efficiency before the repository may claim that eight physical stacks are frozen.
Changing to the 36 GB, 12-high profile would require a capacity/topology decision because eight such
stacks provide 288 GB rather than the baselined 192 GB.
