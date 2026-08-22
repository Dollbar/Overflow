import json
from pathlib import Path

from kdlink_model.chassis import ChassisTopology, LinkState


def test_all_endpoint_mappings_round_trip() -> None:
    chassis = ChassisTopology()
    observed = set()
    for slot_id in range(8):
        for local_npu in range(4):
            for plane_id in range(8):
                for slice_id in range(2):
                    endpoint = chassis.endpoint_index(slot_id, local_npu, plane_id, slice_id)
                    location = chassis.decode_endpoint(endpoint)
                    assert location.slot_id == slot_id
                    assert location.local_npu == local_npu
                    assert location.plane_id == plane_id
                    assert location.slice_id == slice_id
                    assert location.node_id == slot_id * 4 + local_npu
                    observed.add(endpoint)
    assert observed == set(range(512))


def test_card_and_plane_isolation() -> None:
    chassis = ChassisTopology()
    assert all(chassis.endpoint_available(index) for index in range(512))
    chassis.remove_card(3)
    for endpoint in range(512):
        location = chassis.decode_endpoint(endpoint)
        assert chassis.endpoint_available(endpoint) is (location.slot_id != 3)
    chassis.disable_plane(6)
    for endpoint in range(512):
        location = chassis.decode_endpoint(endpoint)
        expected = location.slot_id != 3 and location.plane_id != 6
        assert chassis.endpoint_available(endpoint) is expected


def test_lane_failure_is_degraded_and_local() -> None:
    chassis = ChassisTopology()
    endpoint = chassis.endpoint_index(7, 3, 7, 1)
    neighbour = chassis.endpoint_index(7, 3, 7, 0)
    chassis.fail_lane(endpoint, 4)
    assert chassis.links[endpoint].state is LinkState.DEGRADED
    assert not chassis.endpoint_available(endpoint)
    assert chassis.links[neighbour].state is LinkState.UP
    assert chassis.endpoint_available(neighbour)


def test_training_and_admin_state() -> None:
    chassis = ChassisTopology()
    link = chassis.links[0]
    link.training_complete = False
    assert link.state is LinkState.TRAINING
    link.admin_up = False
    assert link.state is LinkState.DOWN


def test_versioned_chassis_configuration_matches_model() -> None:
    config_path = Path(__file__).parents[2] / "config" / "chassis32.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    assert config["schema_version"] == 1
    assert config["card_slots"] == 8
    assert config["npus_per_card"] == 4
    assert config["nodes"] == 32
    assert config["planes"] == 8
    assert config["pcs"]["lanes_per_slice"] == 10
    assert config["pcs"]["block_width_bits"] == 66
