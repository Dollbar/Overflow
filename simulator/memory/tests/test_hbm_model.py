from pathlib import Path

import pytest
import yaml

from hbm_model import HBMConfig, HBMModel


ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = ROOT / "Library" / "models" / "hbm" / "hbm.yaml"


def load_config(**overrides: int) -> HBMConfig:
    values = HBMConfig.from_yaml(CONFIG_PATH).__dict__ | overrides
    return HBMConfig(**values)


def load_profile(profile: str) -> HBMConfig:
    return HBMConfig.from_yaml(CONFIG_PATH, profile=profile)


def test_configuration_matches_system_capacity_and_bandwidth() -> None:
    config = load_config()
    baseline = yaml.safe_load((ROOT / "config" / "system_baseline.yaml").read_text())
    proposal = yaml.safe_load((ROOT / "config" / "npu_arch_proposed.yaml").read_text())
    assert config.partitions == proposal["organization"]["hbm_partitions_per_npu"]
    assert config.capacity_bytes_per_partition == proposal["hbm"]["capacity_gbyte_per_partition"] * 1_000_000_000
    assert config.total_capacity_bytes == 192_000_000_000
    assert baseline["system"]["logical_hbm_gbyte_per_npu"] == 192
    assert config.logical_clock_hz == baseline["npu"]["logical_hbm_clock_hz"]
    assert config.logical_cycle_ns == 1.0
    assert config.payload_bytes_per_second_per_partition == 625_000_000_000
    assert config.aggregate_payload_bytes_per_second == 5_000_000_000_000
    assert config.aggregate_payload_bytes_per_second / 1.0e12 == proposal["hbm"]["target_aggregate_tbyte_per_second"]
    assert proposal["hbm"]["bandwidth_definition"] == "aggregate_read_plus_write_payload"
    assert baseline["npu"]["logical_hbm_bandwidth_definition"] == "aggregate_read_plus_write_payload"
    assert config.read_latency_ns == proposal["assumptions"]["hbm_round_trip_latency_ns_nominal"]


def test_stress_profile_applies_the_versioned_latency_override() -> None:
    config = load_profile("stress")
    assert config.read_latency_cycles == 800
    assert config.write_latency_cycles == 800
    assert config.read_latency_ns == 800.0
    assert config.aggregate_payload_bytes_per_second == 5_000_000_000_000


def test_unknown_profile_is_rejected() -> None:
    with pytest.raises(ValueError, match="nominal or stress"):
        load_profile("turbo")


def test_sparse_storage_preserves_partitioned_read_write_order() -> None:
    model = HBMModel(load_config(read_latency_cycles=3, write_latency_cycles=3))
    payload = bytes(range(128))
    assert model.submit_write(3, 256, payload, tag=10)
    assert model.submit_read(3, 256, 128, tag=11)
    assert model.submit_read(4, 256, 128, tag=12)
    model.run_until_idle()
    responses = {response.tag: response for response in model.drain_responses()}
    assert responses[10].is_write and responses[10].data == b""
    assert responses[11].data == payload
    assert responses[12].data == bytes(128)
    assert responses[11].completion_cycle - model.stats.first_issue_cycle == 3


def test_bandwidth_token_bucket_reaches_declared_payload_rate() -> None:
    model = HBMModel(load_config(read_latency_cycles=1, max_outstanding_per_partition=256))
    for tag in range(100):
        assert model.submit_read(0, tag * 128, 128, tag)
    model.run_until_idle()
    assert model.stats.first_issue_cycle == 1
    assert model.stats.last_issue_cycle == 21
    assert model.stats.accepted_read_bytes == 12_800
    assert model.stats.completed_requests == 100


def test_all_partitions_reach_the_declared_aggregate_payload_rate() -> None:
    model = HBMModel(load_config(read_latency_cycles=1, max_outstanding_per_partition=256))
    for partition in range(model.config.partitions):
        for index in range(100):
            assert model.submit_read(partition, index * 128, 128, tag=partition * 100 + index)
    model.run_until_idle()
    assert model.stats.first_issue_cycle == 1
    assert model.stats.last_issue_cycle == 21
    assert model.stats.accepted_read_bytes == 102_400
    assert model.stats.completed_requests == 800


def test_reads_and_writes_share_one_partition_payload_budget() -> None:
    model = HBMModel(load_config(read_latency_cycles=1, write_latency_cycles=1, max_outstanding_per_partition=256))
    for index in range(100):
        address = index * 128
        if index % 2:
            assert model.submit_write(0, address, bytes([index]) * 128, tag=index)
        else:
            assert model.submit_read(0, address, 128, tag=index)
    model.run_until_idle()
    assert model.stats.last_issue_cycle == 21
    assert model.stats.accepted_read_bytes == 6_400
    assert model.stats.accepted_write_bytes == 6_400
    assert model.stats.accepted_payload_bytes == 12_800


def test_outstanding_limit_applies_backpressure() -> None:
    model = HBMModel(load_config(read_latency_cycles=5, max_outstanding_per_partition=2))
    assert model.submit_read(0, 0, 128, tag=0)
    assert model.submit_read(0, 128, 128, tag=1)
    assert not model.submit_read(0, 256, 128, tag=2)
    assert model.stats.backpressure_events == 1
    model.run_until_idle()
    assert model.outstanding(0) == 0


def test_partition_completion_order_survives_mixed_latency() -> None:
    model = HBMModel(load_config(read_latency_cycles=1, write_latency_cycles=5))
    payload = bytes([0xA5]) * 128
    assert model.submit_write(0, 0, payload, tag=20)
    assert model.submit_read(0, 0, 128, tag=21)
    assert model.submit_read(1, 0, 128, tag=22)
    model.run_until_idle()
    responses = model.drain_responses()
    partition_zero = [response for response in responses if response.partition == 0]
    assert [response.tag for response in partition_zero] == [20, 21]
    assert partition_zero[1].data == payload
    assert next(response for response in responses if response.tag == 22).completion_cycle < partition_zero[0].completion_cycle


def test_maximum_transaction_and_last_partition_beat_are_accepted() -> None:
    config = load_config(read_latency_cycles=1, write_latency_cycles=1)
    model = HBMModel(config)
    address = config.capacity_bytes_per_partition - config.maximum_transaction_bytes
    payload = bytes([0x5A]) * config.maximum_transaction_bytes
    assert model.submit_write(config.partitions - 1, address, payload, tag=30)
    assert model.submit_read(config.partitions - 1, address, len(payload), tag=31)
    model.run_until_idle()
    responses = model.drain_responses()
    assert responses[0].is_write
    assert responses[1].data == payload


@pytest.mark.parametrize(
    "overrides",
    [
        {"logical_clock_hz": 0},
        {"capacity_bytes_per_partition": 129},
        {"maximum_transaction_bytes": 129},
    ],
)
def test_invalid_configurations_are_rejected(overrides: dict[str, int]) -> None:
    with pytest.raises(ValueError):
        HBMModel(load_config(**overrides))


@pytest.mark.parametrize(
    "partition,address,length",
    [(-1, 0, 128), (8, 0, 128), (0, 1, 128), (0, 0, 64), (0, 24_000_000_000, 128)],
)
def test_invalid_transactions_are_rejected(partition: int, address: int, length: int) -> None:
    model = HBMModel(load_config())
    with pytest.raises(ValueError):
        model.submit_read(partition, address, length, tag=0)
