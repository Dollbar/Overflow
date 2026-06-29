#!/usr/bin/env python3
"""Audit the intentionally narrow multi-clock structure of the NPU NoC CDC."""

from __future__ import annotations

import argparse
from pathlib import Path


REQUIRED_FIFO_FRAGMENTS = (
    '(* async_reg = "true" *) logic [POINTER_WIDTH-1:0]\n'
    "        read_gray_write_sync1_q;",
    '(* async_reg = "true" *) logic [POINTER_WIDTH-1:0]\n'
    "        read_gray_write_sync2_q;",
    '(* async_reg = "true" *) logic [POINTER_WIDTH-1:0]\n'
    "        write_gray_read_sync1_q;",
    '(* async_reg = "true" *) logic [POINTER_WIDTH-1:0]\n'
    "        write_gray_read_sync2_q;",
    "read_gray_write_sync1_q <= read_gray_q;",
    "read_gray_write_sync2_q <= read_gray_write_sync1_q;",
    "write_gray_read_sync1_q <= write_gray_q;",
    "write_gray_read_sync2_q <= write_gray_read_sync1_q;",
    "write_gray_next = (write_binary_next >> 1) ^ write_binary_next;",
    "read_gray_next = (read_binary_next >> 1) ^ read_binary_next;",
)


def require_fragments(path: Path, fragments: tuple[str, ...]) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        rendered = "\n".join(f"  {fragment!r}" for fragment in missing)
        raise RuntimeError(f"{path}: required CDC structure missing:\n{rendered}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    noc_dir = args.repo_root.resolve() / "rtl" / "npu" / "noc"
    fifo = noc_dir / "npu_noc_async_fifo.sv"
    pod_cdc = noc_dir / "npu_noc_pod_cdc.sv"
    cdc_mesh = noc_dir / "npu_noc_cdc_mesh.sv"

    require_fragments(fifo, REQUIRED_FIFO_FRAGMENTS)
    require_fragments(
        pod_cdc,
        (
            "module npu_noc_pod_cdc",
            "npu_noc_async_fifo #(",
            ".write_data_i({{CONTROL_PAD{1'b0}}, pod_control_tx_flit_i})",
            ".write_data_i({{DATA_PAD{1'b0}}, pod_data_tx_flit_i[",
            ".write_data_i({{DATA_PAD{1'b0}}, noc_data_rx_flit_i[",
        ),
    )
    require_fragments(
        cdc_mesh,
        (
            "npu_noc_reset_sync u_noc_reset_sync",
            "npu_noc_reset_sync u_pod_reset_sync",
            "npu_noc_pod_cdc u_pod_cdc",
            "npu_noc_level_sync u_pod_busy_to_noc_sync",
            "npu_noc_level_sync #(\n                .RESET_VALUE(1'b1)",
        ),
    )

    pod_cdc_text = pod_cdc.read_text(encoding="utf-8")
    if "always_ff" in pod_cdc_text or "always_latch" in pod_cdc_text:
        raise RuntimeError(
            f"{pod_cdc}: wrapper added state outside the reviewed FIFO primitives"
        )
    if pod_cdc_text.count("npu_noc_async_fifo #(") != 4:
        raise RuntimeError(
            f"{pod_cdc}: expected two control and two generated data FIFO sites"
        )

    print(
        "NPU_NOC_CDC_STRUCTURE_PASS "
        "gray_sync_chains=2 wrapper_fifo_sites=4 payload_padding=checked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
