import pytest

from kdlink_model.performance import fabric_performance


def test_final_kdlink_v2_bandwidth_contract() -> None:
    result = fabric_performance()
    assert result.payload_gbyte_s_per_slice_per_direction == 64.0
    assert result.payload_gbyte_s_per_bonded_port_per_direction == 128.0
    assert result.payload_gbyte_s_per_npu_per_direction == 1024.0
    assert result.payload_gbyte_s_per_npu_full_duplex == 2048.0
    assert result.encoded_gbyte_s_per_slice_per_direction == 82.5
    assert result.payload_encoding_efficiency == pytest.approx(512.0 / 660.0)


def test_32_node_switch_and_allreduce_contract() -> None:
    result = fabric_performance()
    assert result.plane_payload_gbyte_s_per_direction == 4096.0
    assert result.system_payload_gbyte_s_per_direction == 32768.0
    assert result.ring_allreduce_tensor_gbyte_s_per_npu == pytest.approx(1024.0 / 1.9375)
