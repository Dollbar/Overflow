# KDLink Multi-Corner Partitioned OpenSTA

KDLink timing is checked on registered logic partitions. The flow deliberately avoids a flat endpoint or
32-node-fabric claim because replay memories, tensor queues, switch VOQs, PHY hard macros, clock trees, and
post-route parasitics require implementation-specific models.

The repository distributes synthetic HBM/SerDes interface Liberty views for fast, typical, and slow
front-end scenarios. The flow validates their checksums and timing arcs, runs their setup/hold smoke STA,
and reads the matching interface view during each KDLink partition analysis. These interface views are not
vendor macro characterization.

Standard-cell Liberty files remain external and must not be uploaded. For an open-source single-corner
diagnostic, check out OpenROAD-flow-scripts below the repository root and use its Nangate45 library:

```bash
git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
  third_party/OpenROAD-flow-scripts
git -C third_party/OpenROAD-flow-scripts checkout \
  7ff3adf8eda37712a40591dbd8ec3bef449e6fee
OPENROAD_FLOW_ROOT="${OPENROAD_FLOW_ROOT:-third_party/OpenROAD-flow-scripts}"
python3 verification/kdlink/scripts/run_sta.py \
  --period-ns 1.000 \
  --setup-uncertainty-ns 0.100 \
  --hold-uncertainty-ns 0.020 \
  --driving-cell BUF_X1 \
  --liberty \
  "$OPENROAD_FLOW_ROOT/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"
```

For multi-corner closure, provide three characterized libraries through environment variables. Each corner
is mapped independently rather than reusing a netlist from another corner:

```bash
: "${KDLINK_FAST_LIBERTY:?set KDLINK_FAST_LIBERTY}"
: "${KDLINK_TYPICAL_LIBERTY:?set KDLINK_TYPICAL_LIBERTY}"
: "${KDLINK_SLOW_LIBERTY:?set KDLINK_SLOW_LIBERTY}"
python3 verification/kdlink/scripts/run_sta.py \
  --period-ns 1.000 \
  --setup-uncertainty-ns 0.100 \
  --hold-uncertainty-ns 0.020 \
  --driving-cell "${KDLINK_DRIVING_CELL:?set KDLINK_DRIVING_CELL}" \
  --corner "fast=$KDLINK_FAST_LIBERTY" \
  --corner "typical=$KDLINK_TYPICAL_LIBERTY" \
  --corner "slow=$KDLINK_SLOW_LIBERTY"
```

The driving cell must be a valid non-inverting buffer in every supplied standard-cell library. The flow
uses Yosys for timing-driven mapping and OpenSTA with separate 0.100 ns setup and 0.020 ns hold clock
uncertainty, 0.100 ns input/output delay, and 0.005 pF output load. The legacy single-library `--liberty`
form remains available for diagnostics but does not constitute multi-corner closure.

Expected outputs are `verification/kdlink/sta/summary.json`, per-corner mapped netlists and reports below
`verification/kdlink/sta/work/`, and interface reports below `technology/work/interface_sta/`. Work
directories are ignored by Git. The summary records setup and hold slack for every corner and partition,
the external standard-cell library labels, and the repository-distributed interface Liberty labels.

A 1 GHz PASS means every reported partition has nonnegative setup and hold slack in every supplied corner,
and all three interface-Liberty checks pass. It is pre-layout cell-delay and synthetic-interface evidence,
not signoff timing for the complete chip, HBM PHY, or analog SerDes. The next implementation step is to
replace the synthetic interface views with licensed controller/PHY/transceiver Liberty and add extracted
interconnect, clock-tree, package, and board constraints.
