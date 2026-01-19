#!/usr/bin/env python3
"""Run portable KDLink functional-model and RTL simulations."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
PACKAGE_ROOT = ROOT / "simulator" / "kdlink"
MANIFEST_PATH = PACKAGE_ROOT / "manifest.json"
BUILD_ROOT = PACKAGE_ROOT / "work"
GROUPS = ("unit", "subsystem", "system")


def load_tests() -> dict[str, dict[str, Any]]:
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("tests"), dict):
        raise SystemExit(f"invalid manifest: {MANIFEST_PATH.relative_to(ROOT)}")
    return data["tests"]


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def validate_sources(name: str, config: dict[str, Any]) -> list[str]:
    sources = [*config["rtl"], config["testbench"]]
    missing = [source for source in sources if not (ROOT / source).is_file()]
    if missing:
        raise SystemExit(f"{name}: missing source files: {', '.join(missing)}")
    return sources


def run_command(command: list[str], log_path: Path, timeout: int, env: dict[str, str] | None = None) -> str:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            text=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        log_path.write_text(output + f"\nTIMEOUT after {timeout} seconds\n", encoding="utf-8")
        raise SystemExit(f"command timed out; see {relative(log_path)}") from error
    log_path.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"command failed with exit code {result.returncode}; see {relative(log_path)}")
    return result.stdout


def run_rtl_test(name: str, config: dict[str, Any], verilator: str, jobs: int, timeout: int) -> None:
    sources = validate_sources(name, config)
    test_root = BUILD_ROOT / "rtl" / name
    object_root = test_root / "obj"
    if object_root.exists():
        shutil.rmtree(object_root)
    object_root.mkdir(parents=True, exist_ok=True)

    top = config["top"]
    command = [
        verilator,
        "--binary",
        "--timing",
        "-j",
        str(jobs),
        "-Wall",
        "-Wno-TIMESCALEMOD",
        "-Wno-PINCONNECTEMPTY",
        "-Wno-PINMISSING",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-SYNCASYNCNET",
        "-Wno-BLKSEQ",
        "--top-module",
        top,
        "-Irtl/kdlink",
        "-Mdir",
        relative(object_root),
        *sources,
    ]
    (test_root / "command.txt").write_text(shlex.join(command) + "\n", encoding="utf-8")
    run_command(command, test_root / "build.log", timeout)

    binary = object_root / f"V{top}"
    if not binary.is_file():
        raise SystemExit(f"{name}: Verilator did not create {relative(binary)}")
    output = run_command([str(binary)], test_root / "simulation.log", timeout)
    signature = config["pass_signature"]
    if signature not in output:
        raise SystemExit(f"{name}: missing pass signature {signature}; see {relative(test_root / 'simulation.log')}")
    print(f"[RTL_SIM PASS] {name}")


def run_model_tests(timeout: int) -> None:
    tests = sorted((PACKAGE_ROOT / "model" / "tests").glob("test_kdlink_*.py"))
    if not tests:
        raise SystemExit("no KDLink model tests found")
    env = os.environ.copy()
    model_path = str(PACKAGE_ROOT / "model")
    env["PYTHONPATH"] = model_path + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    cache_path = BUILD_ROOT / "model" / ".pytest_cache"
    command = [
        sys.executable,
        "-m",
        "pytest",
        "-q",
        "-o",
        f"cache_dir={relative(cache_path)}",
        *[relative(path) for path in tests],
    ]
    output = run_command(command, BUILD_ROOT / "model" / "pytest.log", timeout, env)
    print(output.rstrip())
    print("[FUNCTIONAL_SIM PASS] kdlink_model")


def list_tests(tests: dict[str, dict[str, Any]]) -> None:
    for group in GROUPS:
        print(f"{group}:")
        for name, config in tests.items():
            if config["group"] == group:
                print(f"  {name:<24} {config['top']}")


def clean_build() -> None:
    expected = ROOT / "simulator" / "kdlink" / "work"
    if BUILD_ROOT.resolve() != expected.resolve():
        raise SystemExit("refusing to clean an unexpected path")
    if BUILD_ROOT.exists():
        shutil.rmtree(BUILD_ROOT)
    print(f"removed {relative(BUILD_ROOT)}")


def parse_args(test_names: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--list", action="store_true", help="list RTL tests")
    action.add_argument("--model", action="store_true", help="run functional-model tests")
    action.add_argument("--test", choices=test_names, help="run one RTL test")
    action.add_argument("--group", choices=(*GROUPS, "all"), help="run an RTL test group")
    action.add_argument("--clean", action="store_true", help="remove only KDLink simulator build outputs")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1), help="Verilator build jobs")
    parser.add_argument("--timeout", type=int, default=1200, help="per-command timeout in seconds")
    args = parser.parse_args()
    if args.jobs < 1 or args.timeout < 1:
        parser.error("--jobs and --timeout must be positive")
    return args


def main() -> None:
    tests = load_tests()
    args = parse_args(sorted(tests))
    if args.list:
        list_tests(tests)
        return
    if args.clean:
        clean_build()
        return
    if args.model:
        run_model_tests(args.timeout)
        return

    verilator = shutil.which("verilator")
    if verilator is None:
        raise SystemExit("verilator was not found in PATH")
    if args.test:
        selected = [args.test]
    else:
        selected = [
            name
            for name, config in tests.items()
            if args.group == "all" or config["group"] == args.group
        ]
    for name in selected:
        run_rtl_test(name, tests[name], verilator, args.jobs, args.timeout)
    print(f"[RTL_SIM PASS] {len(selected)} test(s)")


if __name__ == "__main__":
    main()
