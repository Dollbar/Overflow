from pathlib import Path

from hbm_model import (
    HBM_ECC_CORRECTED,
    HBM_ECC_UNCORRECTABLE,
    HBM_OK,
    HBMConfig,
    HBMModel,
)


ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = ROOT / "Library" / "models" / "hbm" / "hbm.yaml"


def config(**overrides: object) -> HBMConfig:
    values = HBMConfig.from_yaml(CONFIG_PATH).__dict__ | overrides
    return HBMConfig(**values)


def test_all_versioned_profiles_load_with_expected_modes() -> None:
    nominal = HBMConfig.from_yaml(CONFIG_PATH)
    stress = HBMConfig.from_yaml(CONFIG_PATH, profile="stress")
    banked = HBMConfig.from_yaml(CONFIG_PATH, profile="banked_nominal")
    banked_stress = HBMConfig.from_yaml(CONFIG_PATH, profile="banked_stress")
    assert not nominal.timing_model_enabled
    assert stress.read_latency_cycles == 800
    assert banked.timing_model_enabled and banked.refresh_enabled
    assert banked.scheduler_policy == "fr_fcfs"
    assert banked_stress.max_issues_per_partition_per_cycle == 1
    assert banked_stress.refresh_duration_cycles == 260


def test_public_hbm3e_reference_profiles_load() -> None:
    profile_root = CONFIG_PATH.parent / "profiles"
    hbm_24 = HBMConfig.from_yaml(profile_root / "hbm3e_24gb_public_reference.yaml")
    hbm_36 = HBMConfig.from_yaml(profile_root / "hbm3e_36gb_public_reference.yaml")
    assert hbm_24.total_capacity_bytes == 24_000_000_000
    assert hbm_36.total_capacity_bytes == 36_000_000_000
    assert hbm_24.pseudo_channels_per_partition == 32
    assert hbm_24.aggregate_payload_bytes_per_second == 1_200_000_000_000


def test_address_decode_covers_channel_bank_group_row_and_column() -> None:
    model = HBMModel(config())
    first = model.decode_address(0, 0)
    next_bank_group = model.decode_address(0, 4 * model.config.bank_interleave_bytes)
    next_channel = model.decode_address(
        0,
        model.config.banks_per_pseudo_channel
        * model.config.pseudo_channels_per_channel
        * model.config.bank_interleave_bytes,
    )
    next_row = model.decode_address(
        0,
        model.config.banks_per_partition * model.config.row_bytes,
    )
    assert (first.channel, first.pseudo_channel, first.bank_group, first.bank, first.row) == (0, 0, 0, 0, 0)
    assert next_bank_group.bank_group == 1
    assert next_channel.channel == 1
    assert next_row.linear_bank == 0 and next_row.row == 1


def test_byte_enable_updates_only_selected_bytes() -> None:
    model = HBMModel(config(read_latency_cycles=1, write_latency_cycles=1))
    assert model.submit_write(0, 0, bytes([0xAA]) * 128, tag=1)
    model.run_until_idle()
    enables = bytes([1] * 64 + [0] * 64)
    assert model.submit_write(0, 0, bytes([0x55]) * 128, tag=2, byte_enable=enables)
    assert model.submit_read(0, 0, 128, tag=3)
    model.run_until_idle()
    response = next(item for item in model.drain_responses() if item.tag == 3)
    assert response.status == HBM_OK
    assert response.data == bytes([0x55]) * 64 + bytes([0xAA]) * 64


def test_ecc_corrects_single_bit_and_reports_double_bit_error() -> None:
    model = HBMModel(config(read_latency_cycles=1, write_latency_cycles=1))
    payload = bytes([0xA5]) * 128
    assert model.submit_write(0, 0, payload, tag=1)
    model.run_until_idle()
    model.drain_responses()

    model.inject_bit_errors(0, 0, [0], persistent=False)
    assert model.submit_read(0, 0, 128, tag=2)
    model.run_until_idle()
    corrected = model.pop_response()
    assert corrected is not None
    assert corrected.status == HBM_ECC_CORRECTED
    assert corrected.corrected_bits == 1
    assert corrected.data == payload

    model.inject_bit_errors(0, 0, [0, 1], persistent=True)
    assert model.submit_read(0, 0, 128, tag=3)
    model.run_until_idle()
    uncorrectable = model.pop_response()
    assert uncorrectable is not None
    assert uncorrectable.status == HBM_ECC_UNCORRECTABLE
    assert uncorrectable.data[0] == (payload[0] ^ 0x03)
    model.clear_faults(0)


def test_disabled_partition_rejects_without_side_effect() -> None:
    model = HBMModel(config())
    model.set_partition_enabled(2, False)
    assert not model.can_accept(2)
    assert not model.submit_read(2, 0, 128, tag=1)
    assert model.outstanding(2) == 0
    assert model.stats.disabled_partition_events == 1
    model.set_partition_enabled(2, True)
    assert model.can_accept(2)


def test_refresh_blocks_issue_and_closes_open_rows() -> None:
    model = HBMModel(
        config(
            timing_model_enabled=True,
            scheduler_policy="fifo",
            max_issues_per_partition_per_cycle=1,
            read_latency_cycles=1,
            activate_cycles=1,
            precharge_cycles=1,
            minimum_row_active_cycles=1,
            column_to_column_cycles=1,
            row_to_row_cycles=1,
            four_activate_window_cycles=4,
            read_to_write_cycles=1,
            write_to_read_cycles=1,
            refresh_enabled=True,
            refresh_interval_cycles=100,
            refresh_duration_cycles=3,
            refresh_stagger_cycles=0,
        )
    )
    model.request_refresh(0)
    model.tick()
    assert model.submit_read(0, 0, 128, tag=1)
    model.tick(2)
    assert model.stats.issued_requests == 0
    model.run_until_idle()
    assert model.stats.refresh_commands >= 1
    assert model.stats.refresh_blocked_cycles >= 3
    assert model.stats.row_misses == 1


def test_banked_mode_reports_row_hit_and_conflict() -> None:
    model = HBMModel(
        config(
            timing_model_enabled=True,
            scheduler_policy="fifo",
            max_issues_per_partition_per_cycle=1,
            read_latency_cycles=1,
            activate_cycles=1,
            precharge_cycles=1,
            minimum_row_active_cycles=1,
            column_to_column_cycles=1,
            row_to_row_cycles=1,
            four_activate_window_cycles=4,
            read_to_write_cycles=1,
            write_to_read_cycles=1,
            refresh_enabled=False,
        )
    )
    same_bank_next_column = model.config.banks_per_partition * model.config.bank_interleave_bytes
    same_bank_next_row = model.config.banks_per_partition * model.config.row_bytes
    assert model.submit_read(0, 0, 128, tag=1)
    assert model.submit_read(0, same_bank_next_column, 128, tag=2)
    assert model.submit_read(0, same_bank_next_row, 128, tag=3)
    model.run_until_idle()
    assert model.stats.row_misses == 1
    assert model.stats.row_hits == 1
    assert model.stats.row_conflicts == 1
    assert [item.tag for item in model.drain_responses()] == [1, 2, 3]


def test_event_log_is_bounded_and_drains() -> None:
    model = HBMModel(config(event_log_depth=3, read_latency_cycles=1))
    assert model.submit_read(0, 0, 128, tag=7)
    model.run_until_idle()
    events = model.drain_events()
    assert len(events) <= 3
    assert events[-1].kind == "completed"
    assert model.drain_events() == []
