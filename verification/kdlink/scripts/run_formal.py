#!/usr/bin/env python3
"""Run the portable KDLink Yosys SAT property suite."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
FORMAL = ROOT / "verification" / "kdlink" / "formal"
WORK = FORMAL / "work"
SUMMARY = FORMAL / "summary.json"
PROOFS = {
    "fifo_credit": "fifo_credit.ys",
    "rx_exact_once": "rx_exact_once.ys",
    "replay_progress": "replay_progress.ys",
    "vc_service": "vc_service.ys",
    "escape_dependency": "escape_dependency.ys",
    "route_pair_order": "route_pair_order.ys",
    "spine_escape": "spine_escape.ys",
    "global_commit_exact_once": "global_commit_exact_once.ys",
    "route_stage_scale": "route_stage_scale.ys",
    "hierarchical_membership": "hierarchical_membership.ys",
    "scale_route_control": "scale_route_control.ys",
    "card_directory": "card_directory.ys",
    "coverage_reachability": "coverage_reachability.ys",
}


def main() -> None:
    yosys = shutil.which("yosys")
    if not yosys:
        raise SystemExit("yosys was not found in PATH")
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    results: dict[str, dict[str, str]] = {}
    failed = False
    for name, script in PROOFS.items():
        log_path = WORK / f"{name}.log"
        result = subprocess.run(
            [yosys, "-ql", str(log_path), str(FORMAL / script)],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        passed = result.returncode == 0 and "SUCCESS" in log_path.read_text(
            encoding="utf-8", errors="replace"
        )
        results[name] = {
            "status": "PASS" if passed else "FAIL",
            "script": str((FORMAL / script).relative_to(ROOT)),
            "log": str(log_path.relative_to(ROOT)),
        }
        print(f"[FORMAL {'PASS' if passed else 'FAIL'}] {name}")
        failed |= not passed
    SUMMARY.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "evidence": "FORMAL_BOUNDED",
                "engine": "Yosys SAT",
                "proofs": results,
                "pass": not failed,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    if failed:
        raise SystemExit("one or more KDLink formal properties failed")


if __name__ == "__main__":
    main()
