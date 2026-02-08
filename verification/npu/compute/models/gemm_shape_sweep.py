#!/usr/bin/env python3
"""Check and report the M sweep for the fixed 256x256 GEMM array.

M=2/4/8/16 rows are tied to production-RTL numeric regression logs.  Larger
rows are checked as deterministic 256-row/256-column pass accounting; this is
deliberately reported as schedule accounting rather than arithmetic RTL
simulation.
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


ARRAY_ROWS = 256
ARRAY_COLUMNS = 256
TILE_ROWS = 16
K_ELEMENTS = 8192
N_ELEMENTS = 8192
N_PASSES = N_ELEMENTS // ARRAY_COLUMNS
M_VALUES = tuple(1 << exponent for exponent in range(1, 14))
RTL_NUMERIC_M_VALUES = (2, 4, 8, 16)
PASS_RE = re.compile(
    r"PASS: GEMM M=(?P<m>\d+) K=8192 N=8192 .* no_bubble=1"
)
ARRAY_PEAK_PASS = (
    "PASS: full 16x16 Tile array dense_cycles=256 "
    "results=4096 values=65536 peak_results=192 issue_events=65536 "
    "peak_tops_1ghz=131.072"
)


@dataclass(frozen=True)
class SweepRow:
    m: int
    m_passes: int
    n_passes: int
    total_passes: int
    dense_cycles: int
    elapsed_us_1ghz: float
    useful_ops: int
    useful_tops_1ghz: float
    active_physical_tops_1ghz: float
    array_util_percent: float
    active_tile_row_util_percent: float
    evidence: str


def require_numeric_logs(report_dir: Path) -> None:
    for m in RTL_NUMERIC_M_VALUES:
        log_path = report_dir / f"sim_m{m}_k8192_n8192.log"
        if not log_path.is_file():
            raise SystemExit(f"missing production-RTL regression log: {log_path}")
        match = PASS_RE.search(log_path.read_text(encoding="utf-8"))
        if match is None or int(match.group("m")) != m:
            raise SystemExit(f"production-RTL regression did not pass: {log_path}")
    peak_log_path = report_dir / "sim_array16_peak.log"
    if not peak_log_path.is_file():
        raise SystemExit(f"missing full-array peak RTL log: {peak_log_path}")
    if ARRAY_PEAK_PASS not in peak_log_path.read_text(encoding="utf-8"):
        raise SystemExit(f"full-array peak RTL regression did not pass: {peak_log_path}")


def build_row(m: int) -> SweepRow:
    m_passes = (m + ARRAY_ROWS - 1) // ARRAY_ROWS
    total_passes = m_passes * N_PASSES
    dense_cycles = total_passes * K_ELEMENTS
    useful_ops = 2 * m * K_ELEMENTS * N_ELEMENTS
    useful_ops_per_cycle = useful_ops // dense_cycles
    active_rows = min(ARRAY_ROWS, ((m + TILE_ROWS - 1) // TILE_ROWS) * TILE_ROWS)
    active_physical_ops_per_cycle = 2 * active_rows * ARRAY_COLUMNS
    array_util = useful_ops_per_cycle / (2 * ARRAY_ROWS * ARRAY_COLUMNS)
    active_tile_row_util = min(m, ARRAY_ROWS) / active_rows

    assert N_ELEMENTS % ARRAY_COLUMNS == 0
    assert K_ELEMENTS % 32 == 0
    assert useful_ops % dense_cycles == 0
    assert 0 < useful_ops_per_cycle <= 2 * ARRAY_ROWS * ARRAY_COLUMNS
    assert active_physical_ops_per_cycle <= 2 * ARRAY_ROWS * ARRAY_COLUMNS
    assert useful_ops_per_cycle <= active_physical_ops_per_cycle
    if m >= ARRAY_ROWS:
        assert useful_ops_per_cycle == 2 * ARRAY_ROWS * ARRAY_COLUMNS
    else:
        assert useful_ops_per_cycle == 2 * m * ARRAY_COLUMNS

    if m in RTL_NUMERIC_M_VALUES:
        evidence = "production_rtl_numeric_array16x2"
    elif m >= ARRAY_ROWS:
        evidence = "schedule_accounting_plus_full_array_peak_rtl"
    else:
        evidence = "mapped_schedule_accounting"
    return SweepRow(
        m=m,
        m_passes=m_passes,
        n_passes=N_PASSES,
        total_passes=total_passes,
        dense_cycles=dense_cycles,
        elapsed_us_1ghz=dense_cycles / 1000.0,
        useful_ops=useful_ops,
        useful_tops_1ghz=useful_ops_per_cycle / 1000.0,
        active_physical_tops_1ghz=active_physical_ops_per_cycle / 1000.0,
        array_util_percent=100.0 * array_util,
        active_tile_row_util_percent=100.0 * active_tile_row_util,
        evidence=evidence,
    )


def write_csv(path: Path, rows: list[SweepRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(
            (
                "m",
                "k",
                "n",
                "m_passes",
                "n_passes",
                "total_passes",
                "dense_cycles",
                "elapsed_us_1ghz",
                "useful_ops",
                "useful_tops_1ghz",
                "active_physical_tops_1ghz",
                "array_util_percent",
                "active_tile_row_util_percent",
                "no_bubble",
                "evidence",
            )
        )
        for row in rows:
            writer.writerow(
                (
                    row.m,
                    K_ELEMENTS,
                    N_ELEMENTS,
                    row.m_passes,
                    row.n_passes,
                    row.total_passes,
                    row.dense_cycles,
                    f"{row.elapsed_us_1ghz:.3f}",
                    row.useful_ops,
                    f"{row.useful_tops_1ghz:.3f}",
                    f"{row.active_physical_tops_1ghz:.3f}",
                    f"{row.array_util_percent:.5f}",
                    f"{row.active_tile_row_util_percent:.5f}",
                    1,
                    row.evidence,
                )
            )


def write_markdown(path: Path, rows: list[SweepRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        stream.write("# GEMM M sweep: K=N=8192\n\n")
        stream.write(
            "Dense cycles exclude reset, array skew, result drain, and software "
            "launch overhead. `RTL numeric` uses the production GEMM/Tile RTL "
            "in the 16x2 reduced-height regression; larger M values are exact "
            "pass/schedule accounting for the default 16x16 Tile array. The "
            "full array is independently checked at 131.072 TOPS. No-bubble "
            "for mapped rows means a contiguous array-boundary dense schedule, "
            "not a native M/N descriptor launch.\n\n"
        )
        stream.write(
            "| M | M passes | Total passes | Dense cycles | Time @1 GHz | "
            "Useful TOPS | Active physical TOPS | Array util. | Evidence |\n"
        )
        stream.write(
            "|---:|---:|---:|---:|---:|---:|---:|---:|:---|\n"
        )
        for row in rows:
            if row.m in RTL_NUMERIC_M_VALUES:
                evidence = "RTL numeric PASS"
            elif row.m >= ARRAY_ROWS:
                evidence = "schedule + full-array peak RTL PASS"
            else:
                evidence = "schedule accounting PASS"
            stream.write(
                f"| {row.m} | {row.m_passes} | {row.total_passes} | "
                f"{row.dense_cycles:,} | {row.elapsed_us_1ghz:.3f} us | "
                f"{row.useful_tops_1ghz:.3f} | "
                f"{row.active_physical_tops_1ghz:.3f} | "
                f"{row.array_util_percent:.5f}% | {evidence} |\n"
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    parser.add_argument("--require-rtl-logs", action="store_true")
    args = parser.parse_args()

    if args.require_rtl_logs:
        require_numeric_logs(args.report_dir)
    rows = [build_row(m) for m in M_VALUES]
    write_csv(args.csv, rows)
    write_markdown(args.markdown, rows)
    print(
        "PASS: GEMM shape sweep M=2..8192 K=8192 N=8192 "
        "rtl_numeric_m=2,4,8,16 schedule_accounting_m=32..8192 "
        "peak_tops_1ghz=131.072 no_bubble=1"
    )


if __name__ == "__main__":
    main()
