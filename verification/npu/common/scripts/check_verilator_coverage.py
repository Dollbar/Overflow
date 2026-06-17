#!/usr/bin/env python3
"""Fail a regression when measured Verilator coverage drops below its baseline."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SUMMARY_RE = re.compile(r"^\s*([a-z_]+)\s*:\s*([0-9]+(?:\.[0-9]+)?)%")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("summary", type=Path)
    parser.add_argument(
        "--minimum",
        action="append",
        default=[],
        metavar="TYPE=PERCENT",
        help="minimum percentage for a coverage type; repeat as needed",
    )
    args = parser.parse_args()

    measured: dict[str, float] = {}
    for line in args.summary.read_text(encoding="utf-8").splitlines():
        match = SUMMARY_RE.match(line)
        if match:
            measured[match.group(1)] = float(match.group(2))

    failures: list[str] = []
    for requirement in args.minimum:
        name, separator, raw_minimum = requirement.partition("=")
        if not separator:
            parser.error(f"invalid --minimum value: {requirement!r}")
        if name not in measured:
            failures.append(f"{name}: missing from coverage summary")
            continue
        minimum = float(raw_minimum)
        if measured[name] < minimum:
            failures.append(
                f"{name}: {measured[name]:.1f}% is below {minimum:.1f}%"
            )

    if failures:
        print("COVERAGE GATE FAIL")
        for failure in failures:
            print(f"  {failure}")
        return 1

    checked = ", ".join(
        f"{requirement.split('=', 1)[0]}={measured[requirement.split('=', 1)[0]]:.1f}%"
        for requirement in args.minimum
    )
    print(f"COVERAGE GATE PASS: {checked}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
