#!/usr/bin/env python3
"""Run the portable v0.1 HBM functional model regression.

Command: ``python3 simulator/memory/scripts/run.py`` or ``make hbm-model``.
Output: ``simulator/memory/work/pytest.log`` and a FUNCTIONAL_SIM pass signature.
Next: run ``python3 simulator/memory/scripts/run_rtl.py`` for the HDL beat BFM.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
PACKAGE_ROOT = ROOT / "simulator" / "memory"
MODEL_ROOT = ROOT / "Library" / "models" / "hbm"
BUILD_ROOT = PACKAGE_ROOT / "work"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=1200, help="regression timeout in seconds")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    return args


def main() -> int:
    args = parse_args()
    environment = os.environ.copy()
    model_path = str(MODEL_ROOT)
    environment["PYTHONPATH"] = model_path + os.pathsep + environment.get("PYTHONPATH", "")
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    command = [
        sys.executable,
        "-m",
        "pytest",
        "-q",
        "-o",
        f"cache_dir={BUILD_ROOT / '.pytest_cache'}",
        str(PACKAGE_ROOT / "tests"),
    ]
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        (BUILD_ROOT / "pytest.log").write_text(output + "\nTIMEOUT\n", encoding="utf-8")
        print(output, end="")
        print(f"HBM model regression timed out after {args.timeout} seconds", file=sys.stderr)
        return 1
    (BUILD_ROOT / "pytest.log").write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="")
    if result.returncode == 0:
        print("[FUNCTIONAL_SIM PASS] hbm_model")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
