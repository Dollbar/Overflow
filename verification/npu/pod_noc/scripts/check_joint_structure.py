#!/usr/bin/env python3
"""Fail if the Pod/NoC production shell loses its frozen integration shape."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()
    rtl_path = root / "rtl/npu/npu_2x4_pod_noc_system.sv"
    filelist_path = root / "verification/npu/pod_noc/npu_pod_noc_system.f"
    rtl = rtl_path.read_text(encoding="utf-8")

    required = {
        "Pod Array instance": "npu_2x4_pod_array #(",
        "CDC Mesh instance": "npu_noc_cdc_mesh #(",
        "synchronized Pod reset": ".pod_rst_i(pod_rst_o)",
        "no direct Pod clear fanout": ".pod_clear_i('0)",
        "synchronized Pod quiesce": ".pod_quiesce_i(pod_quiesce_o)",
        "control TX attachment/CDC link":
            ".pod_control_tx_valid_i(array_control_tx_valid)",
        "control RX CDC/attachment link":
            ".pod_control_rx_valid_o(array_control_rx_valid)",
        "data TX attachment/CDC link":
            ".pod_data_tx_valid_i(array_data_tx_valid)",
        "data RX CDC/attachment link":
            ".pod_data_rx_valid_o(array_data_rx_valid)",
        "NoC-domain status synchronization": "g_status_sync",
        "system protocol summary": "assign system_protocol_error_o",
    }
    missing = [name for name, token in required.items() if token not in rtl]
    if missing:
        raise SystemExit("ERROR: missing joint structure: " + ", ".join(missing))

    forbidden = {
        "direct global clear into Pod Array": ".pod_clear_i(clear_i)",
        "raw global quiesce into Pod Array": ".pod_quiesce_i(quiesce_i)",
    }
    present = [name for name, token in forbidden.items() if token in rtl]
    if present:
        raise SystemExit("ERROR: unsafe joint structure: " + ", ".join(present))

    entries = [
        line.strip()
        for line in filelist_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    missing_files = [entry for entry in entries if not (root / entry).is_file()]
    if missing_files:
        raise SystemExit("ERROR: missing filelist entries: " + ", ".join(missing_files))
    if entries[-1] != "rtl/npu/npu_2x4_pod_noc_system.sv":
        raise SystemExit("ERROR: production system top must be last in the RTL filelist")

    print(
        "JOINT_STRUCTURE_PASS "
        f"rtl_modules=2 status_sync_classes=8 filelist_entries={len(entries)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
