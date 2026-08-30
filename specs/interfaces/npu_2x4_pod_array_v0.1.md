# NPU 2 by 4 Pod Array Boundary v0.1

Status: baselined structural integration contract; NoC router behavior remains externally owned.

`npu_2x4_pod_array` instantiates eight managed Pods and eight router-independent NoC attachments. Pod ID is
`row * 4 + column`, producing rows `{0,1,2,3}` and `{4,5,6,7}`. Each Pod contains two compute clusters,
one sixteen-channel DMA engine, one shared SRAM, and binds its five-lane HBM boundary to the HBM partition
with the same numeric ID.

Commands and completions are per-Pod vectors. Upstream logic presents a command only to its matching Pod
lane; the Pod gateway independently checks the embedded ID. HBM, result, event, status, and command-counter
buses are flattened with Pod 0 in the least-significant slice.

Every Pod has its own clock, synchronous reset, clear, and quiesce input. Its NoC attachment runs in that
same Pod clock domain. Router-facing ports therefore remain explicitly per-Pod clock-domain interfaces. A
NoC implementation using another clock must supply and verify its own CDC/RDC wrapper.

The array contains no router, mesh links, routing table, virtual channel, credit counter, arbitration,
deadlock policy, packet payload adapter, global scheduler, HBM controller, or PHY. The `noc_*` ports are the
complete handoff to the NoC owner described by `npu_pod_noc_attachment_v0.1.md`.

Structural verification elaborates all eight production managed-Pod control/DMA hierarchies and NoC
attachments, with the large compute and shared-SRAM storage replaced by their verified integration models.
A separate lint target elaborates one real-module compute/DMA/KD28-SRAM Pod hierarchy with reduced Tensor
array dimension. Together they check fixed 2-by-4/five-lane geometry and preserve every generated Pod ID and
HBM affinity. Attachment simulation does not constitute router or congestion verification.
