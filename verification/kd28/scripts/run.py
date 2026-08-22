#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run KD28 Verilator RTL simulation and Yosys fixed-black-box link checks."""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / "verification" / "kd28" / "work"
RTL_WORK = WORK / "rtl"
YOSYS_WORK = WORK / "yosys"
SOURCES = [
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_sp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_sdp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_tdp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_cells.v",
    ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_sync_fifo.v",
    ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_async_fifo.v",
    ROOT / "verification" / "kd28" / "tb" / "tb_kd28_sram_fifo.v",
]


def run_logged(command: list[str], log: Path) -> subprocess.CompletedProcess[str]:
    """Run one command from the repository root and retain combined output."""
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log.write_text(result.stdout, encoding="utf-8")
    return result


def run_verilator() -> None:
    """Compile and execute the self-checking SRAM and FIFO regression."""
    verilator = shutil.which("verilator")
    if not verilator:
        raise SystemExit("required tool was not found in PATH: verilator")
    RTL_WORK.mkdir(parents=True, exist_ok=True)
    command = [
        verilator,
        "--binary",
        "--timing",
        "-j",
        os.environ.get("JOBS", "4"),
        "-Wall",
        "-Wno-DECLFILENAME",
        "-Wno-WIDTHEXPAND",
        "-Wno-WIDTHTRUNC",
        "--top-module",
        "tb_kd28_sram_fifo",
        "-Mdir",
        str(RTL_WORK / "obj"),
        *[str(path) for path in SOURCES],
    ]
    build = run_logged(command, RTL_WORK / "build.log")
    if build.returncode:
        raise SystemExit(f"KD28 Verilator build failed; inspect {(RTL_WORK / 'build.log').relative_to(ROOT)}")
    binary = RTL_WORK / "obj" / "Vtb_kd28_sram_fifo"
    simulation = run_logged([str(binary)], RTL_WORK / "simulation.log")
    if simulation.returncode:
        raise SystemExit(
            f"KD28 Verilator simulation failed; inspect {(RTL_WORK / 'simulation.log').relative_to(ROOT)}"
        )
    if "[RTL_SIM PASS] kd28_sram_fifo" not in simulation.stdout:
        raise SystemExit("KD28 Verilator simulation omitted its pass signature")
    print("[RTL_SIM PASS] kd28_sram_fifo")


def run_yosys_link() -> None:
    """Prove that all fixed black-box names and ports elaborate under a generic synthesis front end."""
    yosys = shutil.which("yosys")
    if not yosys:
        raise SystemExit("required tool was not found in PATH: yosys")
    YOSYS_WORK.mkdir(parents=True, exist_ok=True)
    blackboxes = ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_blackboxes.v"
    smoke = ROOT / "technology" / "kd28" / "smoke" / "kd28_sta_smoke_top.v"
    script = (
        f"read_verilog -lib {blackboxes}; "
        f"read_verilog {smoke}; "
        "hierarchy -check -top kd28_sta_smoke_top; "
        "proc; check -assert"
    )
    result = run_logged([yosys, "-q", "-p", script], YOSYS_WORK / "link.log")
    if result.returncode:
        raise SystemExit(f"KD28 Yosys link failed; inspect {(YOSYS_WORK / 'link.log').relative_to(ROOT)}")
    print("[GENERIC_SYNTH PASS] kd28_fixed_blackbox_link")


def main() -> int:
    """Run every mandatory KD28 RTL and generic-link validation step."""
    run_verilator()
    run_yosys_link()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
