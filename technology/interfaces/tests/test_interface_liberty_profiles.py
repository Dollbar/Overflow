# SPDX-License-Identifier: Apache-2.0
"""Check that the versioned interface profiles match every Liberty timing arc."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[3]
PROFILE_PATH = ROOT / "Library" / "timing" / "interfaces" / "profiles.yaml"
MANIFEST_PATH = ROOT / "Library" / "timing" / "interfaces" / "manifest.yaml"


def extract_groups(source: str, group: str, name: str | None = None) -> list[str]:
    if name is None:
        pattern = re.compile(rf"\b{re.escape(group)}\s*\(\s*\)\s*\{{")
    else:
        pattern = re.compile(
            rf"\b{re.escape(group)}\s*\(\s*{re.escape(name)}\s*\)\s*\{{"
        )
    groups: list[str] = []
    for match in pattern.finditer(source):
        depth = 1
        cursor = match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
            cursor += 1
        if depth:
            raise AssertionError(f"unterminated {group} group: {name or '<anonymous>'}")
        groups.append(source[match.end() : cursor - 1])
    return groups


def one_group(source: str, group: str, name: str) -> str:
    groups = extract_groups(source, group, name)
    assert len(groups) == 1, f"expected one {group}({name}), found {len(groups)}"
    return groups[0]


def timing_value(pin_source: str, timing_type: str, table: str) -> float:
    matches: list[float] = []
    for timing in extract_groups(pin_source, "timing"):
        if not re.search(rf"\btiming_type\s*:\s*{re.escape(timing_type)}\s*;", timing):
            continue
        value = re.search(
            rf"\b{re.escape(table)}\s*\([^)]*\)\s*\{{[^}}]*\bvalues\s*\(\s*\"([0-9.]+)\"\s*\)",
            timing,
            re.DOTALL,
        )
        assert value is not None, f"missing {table} for {timing_type}"
        matches.append(float(value.group(1)))
    assert len(matches) == 1, f"expected one {timing_type}/{table} arc, found {len(matches)}"
    return matches[0]


def assert_input_arcs(cell: str, pins: tuple[str, ...], setup: float, hold: float) -> None:
    for pin_name in pins:
        pin = one_group(cell, "pin", pin_name)
        assert timing_value(pin, "setup_rising", "rise_constraint") == pytest.approx(setup)
        assert timing_value(pin, "setup_rising", "fall_constraint") == pytest.approx(setup)
        assert timing_value(pin, "hold_rising", "rise_constraint") == pytest.approx(hold)
        assert timing_value(pin, "hold_rising", "fall_constraint") == pytest.approx(hold)


def assert_output_arcs(cell: str, pins: tuple[str, ...], delay: float) -> None:
    for pin_name in pins:
        pin = one_group(cell, "pin", pin_name)
        assert timing_value(pin, "rising_edge", "cell_rise") == pytest.approx(delay)
        assert timing_value(pin, "rising_edge", "cell_fall") == pytest.approx(delay)


def test_profile_values_match_all_liberty_arcs() -> None:
    profiles = yaml.safe_load(PROFILE_PATH.read_text(encoding="ascii"))
    assert profiles["schema_version"] == 1
    assert profiles["evidence_level"] == "ANALYTICAL"
    assert profiles["characterization_status"] == "synthetic_frontend_only"

    for scenario_name, scenario in profiles["scenarios"].items():
        liberty_path = ROOT / scenario["liberty"]
        source = liberty_path.read_text(encoding="ascii")
        hbm = one_group(source, "cell", "OVERFLOW_HBM_PORT_ABSTRACT")
        serdes = one_group(source, "cell", "OVERFLOW_SERDES_SLICE_ABSTRACT")
        assert re.search(r"\bdont_use\s*:\s*true\s*;", hbm)
        assert re.search(r"\bdont_use\s*:\s*true\s*;", serdes)

        assert_input_arcs(
            hbm,
            ("REQ_VALID", "REQ_WRITE", "REQ_DATA"),
            scenario["hbm_setup"],
            scenario["hbm_hold"],
        )
        assert_output_arcs(
            hbm,
            ("REQ_READY", "RSP_VALID", "RSP_ERROR", "RSP_DATA"),
            scenario["hbm_clock_to_response"],
        )
        assert_input_arcs(
            serdes,
            ("TX_VALID", "TX_BLOCK"),
            scenario["serdes_setup"],
            scenario["serdes_hold"],
        )
        assert_output_arcs(
            serdes,
            ("RX_VALID", "RX_BLOCK", "LINK_UP"),
            scenario["serdes_clock_to_receive"],
        )
        print(f"[PROFILE_LIBERTY PASS] {scenario_name}")


def test_interface_manifest_checksums() -> None:
    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="ascii"))
    assert manifest["schema_version"] == 1
    assert manifest["evidence_level"] == "ANALYTICAL"
    assert manifest["boundary"] == "synthetic_scalar_frontend_only"
    for relative_path, expected in manifest["checksums"].items():
        source = ROOT / relative_path
        observed = hashlib.sha256(source.read_bytes()).hexdigest()
        assert observed == expected, relative_path
    print(f"[INTERFACE_MANIFEST PASS] {len(manifest['checksums'])} checksums")
