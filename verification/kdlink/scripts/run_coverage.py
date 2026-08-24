#!/usr/bin/env python3
"""Build, run, merge, and gate source-level KDLink RTL coverage."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "simulator" / "kdlink" / "manifest.json"
WORK = ROOT / "verification" / "kdlink" / "coverage" / "work"
SUMMARY = ROOT / "verification" / "kdlink" / "coverage" / "summary.json"
DEFAULT_TESTS = (
    "credit_bank8",
    "fifo_primitives",
    "vc_ingress8",
    "route_context_codec",
    "route_pair_tx",
    "domain_adapter",
    "spine_router",
    "route_stage_scale",
    "route_stage_profiles",
    "global_commit_codec",
    "global_commit_window",
    "link_manager",
    "replay_timeout",
    "rx_commit_stress",
    "bonded_reorder",
    "context_scheduler16",
    "direct_scheduler32",
    "slice",
    "pcs_deskew10",
    "serdes_pcs_link",
    "tensor_bank_array",
    "nic8",
    "nic8_cdc",
    "pcs",
    "reverse_ctrl",
    "reduction_dtype_ii1",
    "reduction_random",
    "collective_datapath16",
    "switch32_congestion",
    "switch32_permutation",
    "collective32_int32",
    "direct32",
    "fabric32",
    "reliable_endpoint_e2e",
    "route_context_reliable",
    "multidomain_bonded",
    "global_recovery",
    "global_transaction_stress",
    "hierarchical_collective",
    "reliable_reset_recovery",
    "reliable_bonded_endpoint",
    "reliable_nic8_fabric",
)
CRITICAL_MODULES = (
    "kdlink_route_stage.v",
    "kdlink_global_transaction_source.v",
    "kdlink_global_commit_tracker.v",
    "kdlink_global_commit_codec.v",
    "kdlink_group_table.v",
    "kdlink_hierarchical_collective_ctrl.v",
)


def run(command: list[str], log_path: Path) -> str:
    result = subprocess.run(
        command,
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"command failed; see {log_path.relative_to(ROOT)}")
    return result.stdout


def filter_rtl_coverage(raw_path: Path, filtered_path: Path) -> None:
    output = ["# SystemC::Coverage-3\n"]
    for line in raw_path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True):
        if line.startswith("C ") and "\x01f\x02rtl/kdlink/" in line:
            source_line = re.sub(r"\x01h\x02[^']*", "", line)
            source_line = re.sub(
                r"(\x01page\x02[^'\x01]*?)__[^'\x01]*(?=\x01|')",
                r"\1",
                source_line,
            )
            output.append(source_line)
    filtered_path.write_text("".join(output), encoding="utf-8")


def filter_module_coverage(raw_path: Path, filtered_path: Path, filename: str) -> None:
    marker = f"\x01f\x02rtl/kdlink/{filename}"
    output = ["# SystemC::Coverage-3\n"]
    for line in raw_path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True):
        if line.startswith("C ") and marker in line:
            output.append(line)
    filtered_path.write_text("".join(output), encoding="utf-8")


def parse_summary(report: str) -> dict[str, dict[str, float | int]]:
    metrics: dict[str, dict[str, float | int]] = {}
    pattern = re.compile(r"^\s*(line|toggle|branch|expr)\s*:\s*([0-9.]+)%\s*\(\s*(\d+)/\s*(\d+)\)", re.MULTILINE)
    for name, percent, hit, total in pattern.findall(report):
        metrics[name] = {"percent": float(percent), "hit": int(hit), "total": int(total)}
    required = {"line", "toggle", "branch"}
    if not required.issubset(metrics):
        raise SystemExit("coverage report did not contain all required metrics")
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--test", action="append", choices=DEFAULT_TESTS)
    parser.add_argument(
        "--refresh-test",
        action="append",
        choices=DEFAULT_TESTS,
        help="rebuild selected databases while reusing the remaining default-test databases",
    )
    parser.add_argument("--no-gate", action="store_true")
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="re-aggregate existing raw databases after a reporting-only change",
    )
    args = parser.parse_args()
    if args.test and args.refresh_test:
        raise SystemExit("use either --test or --refresh-test, not both")
    tests = DEFAULT_TESTS if args.refresh_test else (tuple(args.test) if args.test else DEFAULT_TESTS)
    refresh_tests = set(args.refresh_test or ())
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))["tests"]
    verilator = shutil.which("verilator")
    coverage_tool = shutil.which("verilator_coverage")
    if not verilator or not coverage_tool:
        raise SystemExit("verilator and verilator_coverage must be available in PATH")
    if WORK.exists() and not args.reuse_existing and not refresh_tests:
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True, exist_ok=True)
    filtered_files: list[Path] = []

    for name in tests:
        config = manifest[name]
        test_root = WORK / name
        object_root = test_root / "obj"
        raw_path = test_root / "coverage.dat"
        simulation_log = test_root / "simulation.log"
        reuse_test = args.reuse_existing or bool(refresh_tests and name not in refresh_tests)
        if reuse_test:
            if not raw_path.is_file() or not simulation_log.is_file():
                raise SystemExit(f"{name}: existing raw database or simulation log is missing")
            output = simulation_log.read_text(encoding="utf-8", errors="replace")
        else:
            if test_root.exists():
                shutil.rmtree(test_root)
            object_root.mkdir(parents=True)
            sources = [*config["rtl"], config["testbench"]]
            build_command = [
                verilator,
                "--binary",
                "--timing",
                "--coverage-line",
                "--coverage-toggle",
                "--coverage-expr",
                "--coverage-fsm",
                "--coverage-max-width",
                "64",
                "-j",
                str(args.jobs),
                "-Wall",
                "-Wno-TIMESCALEMOD",
                "-Wno-PINCONNECTEMPTY",
                "-Wno-PINMISSING",
                "-Wno-UNUSEDSIGNAL",
                "-Wno-SYNCASYNCNET",
                "-Wno-BLKSEQ",
                "-Wno-COVERIGN",
                "-Wno-UNOPTFLAT",
                "--top-module",
                config["top"],
                "-Irtl/kdlink",
                "-Mdir",
                str(object_root.relative_to(ROOT)),
                *sources,
            ]
            run(build_command, test_root / "build.log")
            binary = object_root / f"V{config['top']}"
            output = run(
                [str(binary), f"+verilator+coverage+file+{raw_path}"],
                simulation_log,
            )
        if config["pass_signature"] not in output or not raw_path.is_file():
            raise SystemExit(f"{name}: missing pass signature or coverage database")
        filtered_path = test_root / "rtl_source.dat"
        filter_rtl_coverage(raw_path, filtered_path)
        filtered_files.append(filtered_path)
        print(f"[COVERAGE TEST PASS] {name}")

    merged_path = WORK / "merged_rtl.dat"
    run(
        [coverage_tool, "--write", str(merged_path), *map(str, filtered_files)],
        WORK / "merge.log",
    )
    report = run(
        [coverage_tool, "--report", "summary", str(merged_path)],
        WORK / "summary.txt",
    )
    metrics = parse_summary(report)
    thresholds = {"line": 95.0, "branch": 90.0, "toggle": 95.0}
    passed = all(metrics[name]["percent"] >= limit for name, limit in thresholds.items())
    critical_thresholds = {"line": 90.0, "branch": 80.0, "toggle": 80.0}
    critical_results: dict[str, dict[str, object]] = {}
    for filename in CRITICAL_MODULES:
        module_path = WORK / "per_module" / f"{Path(filename).stem}.dat"
        module_path.parent.mkdir(parents=True, exist_ok=True)
        filter_module_coverage(merged_path, module_path, filename)
        module_report = run(
            [coverage_tool, "--report", "summary", str(module_path)],
            WORK / "per_module" / f"{Path(filename).stem}.txt",
        )
        module_metrics = parse_summary(module_report)
        module_pass = all(
            module_metrics[name]["total"] == 0
            or module_metrics[name]["percent"] >= limit
            for name, limit in critical_thresholds.items()
        )
        critical_results[filename] = {
            "metrics": module_metrics,
            "thresholds_percent": critical_thresholds,
            "pass": module_pass,
        }
        passed &= module_pass
        print(f"[COVERAGE MODULE {'PASS' if module_pass else 'FAIL'}] {filename}")
    summary = {
        "schema_version": 1,
        "evidence": "RTL_COVERAGE",
        "scope": "rtl/kdlink source-level control coverage",
        "aggregation": (
            "union by RTL source point across hierarchy and Verilator "
            "parameterized-page suffixes"
        ),
        "reused_existing_raw_databases": args.reuse_existing or bool(refresh_tests),
        "refreshed_tests": sorted(refresh_tests),
        "tests": list(tests),
        "metrics": metrics,
        "thresholds_percent": thresholds,
        "critical_module_results": critical_results,
        "exclusions": [
            "testbench and behavioral-model source paths",
            "signals and memories wider than 64 bits for toggle coverage",
            "Route Context reserved bits [511:166], which the protocol requires to remain zero",
            "tool-generated underscore-prefixed implementation signals",
        ],
        "pass": passed,
    }
    SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(report.rstrip())
    print(f"[COVERAGE {'PASS' if passed else 'FAIL'}] {SUMMARY.relative_to(ROOT)}")
    if not passed and not args.no_gate:
        raise SystemExit("KDLink coverage thresholds were not met")


if __name__ == "__main__":
    main()
