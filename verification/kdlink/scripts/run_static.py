#!/usr/bin/env python3
"""Run KDLink production-RTL lint and structural CDC audits."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
RTL_ROOT = ROOT / "rtl" / "kdlink"
WORK = ROOT / "verification" / "kdlink" / "cdc" / "work"
SUMMARY = ROOT / "verification" / "kdlink" / "cdc" / "summary.json"
TOPS = (
    "kdlink_reliable_endpoint",
    "kdlink_reliable_bonded_endpoint",
    "kdlink_reliable_nic8",
    "kdlink_collective_datapath16",
    "kdlink_collective32_int32",
    "kdlink_pcs",
    "kdlink_domain_adapter",
    "kdlink_route_pair_tx",
    "kdlink_spine_router",
    "kdlink_route_stage",
    "kdlink_global_transaction_source",
    "kdlink_global_commit_tracker",
    "kdlink_group_table",
    "kdlink_hierarchical_collective_ctrl",
    "kdlink_global_commit_codec",
    "kdlink_scale_route_context_encoder",
    "kdlink_route_digit_selector",
    "kdlink_scale_route_stage",
    "kdlink_scale_global_commit_encoder",
    "kdlink_transaction_window",
    "kdlink_commit_window",
    "kdlink_group_directory",
    "kdlink_collective_tree_ctrl",
    "kdlink_plane_selector",
    "kdlink_route_epoch_manager",
    "kdlink_deadlock_guard",
    "kdlink_card_directory",
)
MULTICLOCK_CONTRACT = {
    "coll_async_fifo.v": ("gray", "sync1", "sync2"),
    "coll_toggle_handshake.v": ("sync1", "sync2"),
    "kdlink_nic8_cdc.v": ("coll_async_fifo",),
    "kdlink_vc_ingress8.v": ("coll_async_fifo",),
    "kdlink_reliable_endpoint.v": ("coll_async_fifo", "coll_toggle_handshake"),
    "kdlink_reliable_bonded_endpoint.v": ("kdlink_reliable_endpoint",),
    "kdlink_reliable_nic8.v": ("kdlink_reliable_bonded_endpoint",),
}


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//.*", "", text)


def main() -> None:
    verilator = shutil.which("verilator")
    if not verilator:
        raise SystemExit("verilator was not found in PATH")
    WORK.mkdir(parents=True, exist_ok=True)
    sources = sorted(RTL_ROOT.glob("*.v"))
    source_args = [str(path.relative_to(ROOT)) for path in sources]
    lint_results: dict[str, str] = {}
    failed = False
    for top in TOPS:
        log_path = WORK / f"lint_{top}.log"
        command = [
            verilator,
            "--lint-only",
            "-Wall",
            "-Wno-MULTITOP",
            "-Wno-PINCONNECTEMPTY",
            "-Wno-PINMISSING",
            "-Wno-UNUSEDSIGNAL",
            "-Wno-SYNCASYNCNET",
            "-Wno-BLKSEQ",
            "-Irtl/kdlink",
            "--top-module",
            top,
            *source_args,
        ]
        result = subprocess.run(
            command,
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        log_path.write_text(result.stdout, encoding="utf-8")
        passed = result.returncode == 0
        lint_results[top] = "PASS" if passed else "FAIL"
        print(f"[LINT {'PASS' if passed else 'FAIL'}] {top}")
        failed |= not passed

    forbidden_findings: list[str] = []
    gated_clock_findings: list[str] = []
    for path in sources:
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for pattern, label in (
            (r"\$(display|fatal|finish|stop)\b", "simulation system task"),
            (r"\b(force|release)\b", "force/release"),
            (r"(^|\s)#[0-9]", "delay control"),
        ):
            if re.search(pattern, text, flags=re.MULTILINE):
                forbidden_findings.append(f"{path.relative_to(ROOT)}: {label}")
        if re.search(r"assign\s+\w*clk\w*\s*=\s*[^;]*[&|]\s*[^;]*;", text, flags=re.IGNORECASE):
            gated_clock_findings.append(str(path.relative_to(ROOT)))

    cdc_results: dict[str, dict[str, object]] = {}
    for name, required_tokens in MULTICLOCK_CONTRACT.items():
        path = RTL_ROOT / name
        text = path.read_text(encoding="utf-8", errors="replace")
        missing = [token for token in required_tokens if token not in text]
        clocks = sorted(set(re.findall(r"\b([A-Za-z0-9_]*clk[A-Za-z0-9_]*)\b", text)))
        passed = not missing
        cdc_results[name] = {
            "status": "PASS" if passed else "FAIL",
            "clock_identifiers": clocks,
            "required_structures": list(required_tokens),
            "missing_structures": missing,
        }
        print(f"[CDC {'PASS' if passed else 'FAIL'}] {name}")
        failed |= not passed

    failed |= bool(forbidden_findings or gated_clock_findings)
    summary = {
        "schema_version": 1,
        "evidence": "LINT+CDC_STRUCTURAL",
        "lint_tops": lint_results,
        "forbidden_rtl_findings": forbidden_findings,
        "raw_gated_clock_findings": gated_clock_findings,
        "cdc_modules": cdc_results,
        "reset_assumption": "asynchronous assertion and synchronous deassertion per receiving domain; paired FIFO domains reset together",
        "pass": not failed,
    }
    SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if failed:
        raise SystemExit("KDLink static lint or CDC audit failed")


if __name__ == "__main__":
    main()
