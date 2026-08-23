# SPDX-License-Identifier: Apache-2.0
"""Validate KD28 macro generation, synthetic profiles, and controlled checksums."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[3]
MACRO_PATH = ROOT / "Library" / "models" / "kd28" / "sram" / "macros.yaml"
PROFILE_PATH = ROOT / "Library" / "timing" / "kd28" / "sram" / "profiles.yaml"
MANIFEST_PATH = ROOT / "Library" / "timing" / "kd28" / "sram" / "manifest.yaml"
CELLS_PATH = ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_cells.v"
BLACKBOX_PATH = ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_blackboxes.v"


def fixed_macro_names(config: dict) -> list[str]:
    """Return the deterministic fixed-cell name set from the macro source file."""
    names: list[str] = []
    for family, family_config in config["families"].items():
        for macro in family_config["macros"]:
            names.append(f"KD28_SRAM_{family}_{macro['depth']}X{macro['width']}")
    return names


def test_fixed_cells_match_macro_source() -> None:
    """Require every controlled macro in behavioral, black-box, and Liberty views."""
    config = yaml.safe_load(MACRO_PATH.read_text(encoding="ascii"))
    assert config["technology"] == "KD28"
    assert config["technology_status"] == "repository_synthetic_not_foundry_pdk"
    names = fixed_macro_names(config)
    assert len(names) == 14
    assert len(names) == len(set(names))
    behavioral = CELLS_PATH.read_text(encoding="ascii")
    blackboxes = BLACKBOX_PATH.read_text(encoding="ascii")
    profiles = yaml.safe_load(PROFILE_PATH.read_text(encoding="ascii"))
    for name in names:
        assert len(re.findall(rf"\bmodule\s+{re.escape(name)}\b", behavioral)) == 1
        assert len(re.findall(rf"\bmodule\s+{re.escape(name)}\b", blackboxes)) == 1
    for scenario_name in profiles["scenarios"]:
        liberty = (
            ROOT / "Library" / "timing" / "kd28" / "sram" / f"kd28_sram_{scenario_name}.lib"
        ).read_text(encoding="ascii")
        for name in names:
            assert len(re.findall(rf"\bcell\s*\(\s*{re.escape(name)}\s*\)", liberty)) == 1
    print(f"[KD28_FIXED_CELLS PASS] {len(names)} macros")


def test_profile_values_reach_each_liberty() -> None:
    """Require each scenario value in setup, hold, and clock-to-output tables."""
    profiles = yaml.safe_load(PROFILE_PATH.read_text(encoding="ascii"))
    assert profiles["evidence_level"] == "ANALYTICAL"
    assert profiles["characterization_status"] == "synthetic_frontend_only"
    for scenario_name, scenario in profiles["scenarios"].items():
        liberty = (
            ROOT / "Library" / "timing" / "kd28" / "sram" / f"kd28_sram_{scenario_name}.lib"
        ).read_text(encoding="ascii")
        setup = f'values ("{float(scenario["setup_ns"]):.3f}")'
        hold = f'values ("{float(scenario["hold_ns"]):.3f}")'
        delay = f'values ("{float(scenario["clock_to_q_ns"]):.3f}")'
        assert liberty.count(setup) >= 14
        assert liberty.count(hold) >= 14
        assert liberty.count(delay) >= 14
        assert "is_macro_cell : true" in liberty
        print(f"[KD28_PROFILE PASS] {scenario_name}")


def test_manifest_checksums() -> None:
    """Reject source or generated-file drift outside the controlled generator flow."""
    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="ascii"))
    assert manifest["technology"] == "KD28"
    assert manifest["evidence_level"] == "ANALYTICAL"
    for relative_path, expected in manifest["checksums"].items():
        source = ROOT / relative_path
        observed = hashlib.sha256(source.read_bytes()).hexdigest()
        assert observed == expected, relative_path
    print(f"[KD28_MANIFEST PASS] {len(manifest['checksums'])} checksums")


def test_fifo_parameters_stay_inside_documented_boundary() -> None:
    """Check fixed-macro FIFO mapping and required Gray-pointer CDC structure."""
    fifo_root = ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl"
    mapper_source = (fifo_root / "kd28_fifo_sdp_storage_map.v").read_text(encoding="ascii")
    sync_source = (fifo_root / "kd28_sync_fifo.v").read_text(encoding="ascii")
    async_source = (fifo_root / "kd28_async_fifo.v").read_text(encoding="ascii")
    cdc_constraints = (
        ROOT / "technology" / "kd28" / "constraints" / "kd28_async_fifo_cdc.sdc"
    ).read_text(encoding="ascii")
    assert re.search(r"parameter\s+DEPTH\s*=\s*16", sync_source)
    assert re.search(r"parameter\s+DEPTH\s*=\s*16", async_source)
    assert 'async_reg = "true"' in async_source
    assert "write_gray_next" in async_source
    assert "read_gray_next" in async_source
    assert "read_gray_wsync1_q <= read_consume_gray_q" in async_source
    assert "read_gray_wsync2_q <= read_gray_wsync1_q" in async_source
    assert "write_gray_rsync1_q <= write_gray_q" in async_source
    assert "write_gray_rsync2_q <= write_gray_rsync1_q" in async_source
    assert "write_gray_next == {~read_gray_wsync2_q" in async_source
    assert "read_gray_q == write_gray_rsync2_q" in async_source
    assert "kd28_fifo_sdp_storage_map" in sync_source
    assert "kd28_fifo_sdp_storage_map" in async_source
    assert "kd28_sram_sdp_model" not in sync_source
    assert "kd28_sram_sdp_model" not in async_source
    for macro_name in (
        "KD28_SRAM_SDP_256X32",
        "KD28_SRAM_SDP_512X64",
        "KD28_SRAM_SDP_1024X128",
        "KD28_SRAM_SDP_2048X256",
    ):
        assert macro_name in mapper_source
    assert "set_clock_groups -asynchronous" in cdc_constraints
    assert "-allow_paths" in cdc_constraints
    assert cdc_constraints.count("set_max_delay") == 2
    assert cdc_constraints.count("-ignore_clock_latency") == 2
    assert len(re.findall(r"^\s*set_bus_skew\s", cdc_constraints, re.MULTILINE)) == 2
    assert "read_gray_wsync1_q" in cdc_constraints
    assert "write_gray_rsync1_q" in cdc_constraints
    print("[KD28_FIFO_STRUCTURE PASS] fixed_macro_mapping async_cdc")
