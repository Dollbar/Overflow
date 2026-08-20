#!/usr/bin/env python3
"""Build and run the reusable HBM beat BFM self-check.

Command: ``python3 simulator/memory/scripts/run_rtl.py`` or ``make hbm-model``.
Outputs: build and simulation logs under ``simulator/memory/work/rtl_bfm``.
Next: integrate ``overflow_hbm_beat_bfm`` with the controller adapter under test.
"""

from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / "simulator" / "memory" / "work" / "rtl_bfm"
TOP = "tb_overflow_hbm_beat_bfm"
PASS_SIGNATURE = "TB_OVERFLOW_HBM_BEAT_BFM_PASS"


def main() -> int:
    verilator = shutil.which("verilator")
    if not verilator:
        raise SystemExit("required tool was not found in PATH: verilator")
    version = subprocess.run(
        [verilator, "--version"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout.strip()
    match = re.search(r"Verilator\s+(\d+)\.(\d+)", version)
    if match is None or (int(match.group(1)), int(match.group(2))) < (5, 50):
        raise SystemExit(f"Verilator 5.050 or newer is required; found: {version}")
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    sources = [
        ROOT / "Library" / "models" / "hbm" / "rtl" / "overflow_hbm_beat_bfm.sv",
        ROOT / "simulator" / "memory" / "tb" / "tb_overflow_hbm_beat_bfm.sv",
    ]
    command = [
        verilator,
        "--binary",
        "--timing",
        "-Wall",
        "-Wno-TIMESCALEMOD",
        "-Wno-WIDTHTRUNC",
        "-Wno-WIDTHEXPAND",
        "-Wno-BLKSEQ",
        "-Wno-UNUSEDSIGNAL",
        "--top-module",
        TOP,
        "-Mdir",
        str(WORK / "obj"),
        *map(str, sources),
    ]
    with (WORK / "build.log").open("w", encoding="ascii") as handle:
        subprocess.run(command, cwd=ROOT, check=True, stdout=handle, stderr=subprocess.STDOUT)
    binary = WORK / "obj" / f"V{TOP}"
    result = subprocess.run(
        [str(binary)], cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    (WORK / "simulation.log").write_text(result.stdout, encoding="ascii")
    if PASS_SIGNATURE not in result.stdout:
        raise SystemExit(f"missing pass signature; inspect {WORK / 'simulation.log'}")
    print(version)
    print("[RTL_SIM PASS] hbm_beat_bfm")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
