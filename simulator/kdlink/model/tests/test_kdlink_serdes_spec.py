import json
from pathlib import Path
import re

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[4]
SERDES_CONFIG = ROOT / "Library" / "models" / "kdlink" / "serdes" / "serdes.yaml"
SERDES_RTL = ROOT / "Library" / "models" / "kdlink" / "serdes" / "kdlink_serdes_channel_model.sv"
SERDES_FULL_RTL = (
    ROOT / "Library" / "models" / "kdlink" / "serdes" / "kdlink_serdes_channel_full_model.sv"
)
SERDES_LANE_RTL = (
    ROOT / "Library" / "models" / "kdlink" / "serdes" / "kdlink_serdes_lane_full_model.sv"
)
SERDES_PROFILES = ROOT / "Library" / "models" / "kdlink" / "serdes" / "profiles"


def load_serdes_config() -> dict:
    return yaml.safe_load(SERDES_CONFIG.read_text(encoding="ascii"))


def test_serdes_transport_matches_chassis_and_protocol_baseline() -> None:
    config = load_serdes_config()
    chassis = json.loads((ROOT / "simulator" / "kdlink" / "config" / "chassis32.json").read_text())
    baseline = yaml.safe_load((ROOT / "config" / "system_baseline.yaml").read_text())
    transport = config["logical_interface"]
    assert config["schema_version"] == 2
    assert config["boundary"] == chassis["behavioral_boundary"]
    assert transport["group_clock_hz"] == baseline["kdlink"]["assumed_logical_port_clock_hz"]
    assert transport["lanes_per_slice"] == chassis["pcs"]["lanes_per_slice"]
    assert transport["pcs_block_bits"] == chassis["pcs"]["block_width_bits"]
    assert transport["blocks_per_group"] == chassis["pcs"]["blocks_per_group"]
    assert transport["logical_flit_bits"] == chassis["pcs"]["logical_flit_bits"]
    assert transport["kdlink_payload_bits_per_flit"] == chassis["pcs"]["payload_bits"]
    assert transport["slices_per_bonded_port"] == chassis["slices_per_port"]


def test_serdes_rate_derivations_are_exact() -> None:
    config = load_serdes_config()
    transport = config["logical_interface"]
    clock_hz = transport["group_clock_hz"]
    rates = config["derived_logical_rates"]
    raw_lane_gbit_s = transport["pcs_block_bits"] * clock_hz / 1.0e9
    raw_slice_gbit_s = raw_lane_gbit_s * transport["lanes_per_slice"]
    pcs_client_gbit_s = (
        transport["pcs_data_bits_per_block"] * transport["blocks_per_group"] * clock_hz / 1.0e9
    )
    payload_gbyte_s = transport["kdlink_payload_bits_per_flit"] * clock_hz / 8.0 / 1.0e9
    assert raw_lane_gbit_s == rates["encoded_gbit_per_second_per_lane"]
    assert raw_slice_gbit_s == rates["encoded_gbit_per_second_per_slice_per_direction"]
    assert pcs_client_gbit_s == rates["pcs_client_gbit_per_second_per_slice_per_direction"]
    assert payload_gbyte_s == rates["kdlink_payload_gbyte_per_second_per_slice_per_direction"]
    assert payload_gbyte_s * transport["slices_per_bonded_port"] == rates[
        "ideal_two_slice_payload_gbyte_per_second_per_direction"
    ]
    baseline_ports = yaml.safe_load((ROOT / "config" / "system_baseline.yaml").read_text())[
        "kdlink"
    ]["target_ports_per_npu"]
    assert (
        payload_gbyte_s * transport["baseline_active_slices_per_port"] * baseline_ports
        == 512.0
    )


def test_serdes_physical_profile_has_capacity_for_logical_groups() -> None:
    config = load_serdes_config()
    baseline = yaml.safe_load((ROOT / "config" / "system_baseline.yaml").read_text())
    physical = config["physical_mapping"]
    line_rate = physical["serial_line_rate_gbit_per_second"] * 1.0e9
    block_capacity = line_rate / config["logical_interface"]["pcs_block_bits"]
    logical_rate = config["logical_interface"]["group_clock_hz"]
    assert physical["selected_profile"] == baseline["kdlink"]["physical_planning_profile"]
    assert physical["serial_line_rate_gbit_per_second"] == baseline["kdlink"][
        "physical_line_rate_gbit_per_second"
    ]
    assert block_capacity == pytest.approx(
        physical["physical_66bit_block_capacity_per_second"], rel=1.0e-12
    )
    assert logical_rate < block_capacity
    assert logical_rate / block_capacity * 100.0 == pytest.approx(
        physical["physical_capacity_utilization_percent"], rel=1.0e-12
    )
    assert config["unsupported_direct_mapping"]["release_claim"] == "HOLD"


def test_all_public_serdes_profiles_have_consistent_rate_derivations() -> None:
    profile_paths = sorted(SERDES_PROFILES.glob("*.yaml"))
    assert len(profile_paths) == 3
    for profile_path in profile_paths:
        profile = yaml.safe_load(profile_path.read_text(encoding="ascii"))
        physical = profile["physical"]
        parameters = profile["model_parameters"]
        line_rate = physical["line_rate_gbit_per_second"]
        block_rate = line_rate * 1.0e9 / 66.0
        declared_block_rate = physical.get(
            "block_group_capacity_hz", physical.get("block_group_clock_hz")
        )
        assert profile["schema_version"] == 1
        assert physical["symbol_rate_gbaud"] == pytest.approx(
            line_rate / physical["bits_per_symbol"], rel=1.0e-12
        )
        assert physical["pcs_data_gbit_per_second_per_lane"] == pytest.approx(
            line_rate * 64.0 / 66.0, rel=1.0e-12
        )
        assert declared_block_rate == pytest.approx(block_rate, rel=1.0e-12)
        assert parameters["line_rate_kbps"] == pytest.approx(line_rate * 1.0e6)
        assert parameters["modulation_bits_per_symbol"] == physical["bits_per_symbol"]


def test_serdes_rtl_defaults_match_the_versioned_configuration() -> None:
    config = load_serdes_config()["channel_defaults"]
    source = SERDES_RTL.read_text(encoding="ascii")
    expected = {
        "PROPAGATION_CYCLES": config["propagation_cycles"],
        "MAX_LANE_SKEW_CYCLES": config["maximum_lane_skew_cycles"],
        "TRAINING_CYCLES": config["compatibility_training_cycles"],
    }
    for parameter, value in expected.items():
        assert re.search(rf"parameter integer {parameter} = {value}\b", source)


def test_full_serdes_rtl_defaults_match_the_versioned_configuration() -> None:
    config = load_serdes_config()["channel_defaults"]
    channel_source = SERDES_FULL_RTL.read_text(encoding="ascii")
    lane_source = SERDES_LANE_RTL.read_text(encoding="ascii")
    channel_expected = {
        "PROPAGATION_CYCLES": config["propagation_cycles"],
        "MAX_LANE_SKEW_CYCLES": config["maximum_lane_skew_cycles"],
        "CDR_LOCK_CYCLES": config["cdr_lock_cycles"],
        "BLOCK_LOCK_CYCLES": config["block_lock_cycles"],
        "LINE_RATE_KBPS": config["line_rate_kbps_metadata"],
        "MODULATION_BITS_PER_SYMBOL": config["modulation_bits_per_symbol"],
    }
    lane_expected = {
        "JITTER_PERIOD_BLOCKS": config["jitter_period_blocks"],
        "JITTER_EXTRA_CYCLES": config["jitter_extra_cycles"],
        "BURST_ERROR_LENGTH_BLOCKS": config["burst_error_length_blocks"],
        "ELASTIC_DEPTH": config["elastic_depth"],
    }
    for parameter, value in channel_expected.items():
        assert re.search(rf"parameter integer {parameter} = {value}\b", channel_source)
    for parameter, value in lane_expected.items():
        assert re.search(rf"parameter integer {parameter} = {value}\b", lane_source)
