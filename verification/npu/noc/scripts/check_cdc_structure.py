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
    "always_ff @(posedge write_clk_i or posedge write_rst_i)",
    "always_ff @(posedge read_clk_i or posedge read_rst_i)",
)

RESET_SYNC_FRAGMENTS = (
    '(* async_reg = "true" *) logic [1:0] release_q;',
    "always_ff @(posedge clk_i or posedge async_rst_i)",
    "release_q <= 2'b11;",
    "release_q <= {release_q[0], 1'b0};",
    "assign sync_rst_o = release_q[1];",
)

LEVEL_SYNC_FRAGMENTS = (
    '(* async_reg = "true" *) logic [1:0] level_q;',
    "always_ff @(posedge clk_i or posedge rst_i)",
    "level_q <= {level_q[0], async_level_i};",
    "assign sync_level_o = level_q[1];",
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
    reset_sync = noc_dir / "npu_noc_reset_sync.sv"
    level_sync = noc_dir / "npu_noc_level_sync.sv"
    pod_cdc = noc_dir / "npu_noc_pod_cdc.sv"
    cdc_mesh = noc_dir / "npu_noc_cdc_mesh.sv"

    require_fragments(fifo, REQUIRED_FIFO_FRAGMENTS)
    require_fragments(reset_sync, RESET_SYNC_FRAGMENTS)
    require_fragments(level_sync, LEVEL_SYNC_FRAGMENTS)
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
    fifo_text = fifo.read_text(encoding="utf-8")
    if fifo_text.count("always_ff @(") != 4:
        raise RuntimeError(
            f"{fifo}: expected exactly two functional clock owners and two "
            "FORMAL-only assertion processes"
        )
    if fifo_text.count('(* async_reg = "true" *)') != 4:
        raise RuntimeError(
            f"{fifo}: expected four explicitly attributed Gray synchronizer stages"
        )
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
        "gray_sync_chains=2 reset_sync=checked level_sync=checked "
        "clock_owners=2 wrapper_fifo_sites=4 payload_padding=checked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
