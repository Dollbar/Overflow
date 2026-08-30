"""Unit tests for the deterministic NPU NoC reference model."""

from __future__ import annotations

import pathlib
import sys
import unittest


MODEL_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_DIR))

import model  # noqa: E402


class NpuNocModelTest(unittest.TestCase):
    """Check geometry, deterministic routes, and traffic accounting."""

    def test_all_directed_routes_are_minimal_and_legal(self) -> None:
        legal_links = model.directed_links()
        self.assertEqual(len(legal_links), 20)
        for source in range(model.PODS):
            source_column, source_row = model.coordinates(source)
            for destination in range(model.PODS):
                destination_column, destination_row = model.coordinates(destination)
                route = model.route_xy(source, destination)
                expected_hops = abs(destination_column - source_column) + abs(
                    destination_row - source_row
                )
                self.assertEqual(len(route) - 1, expected_hops)
                self.assertEqual(len(set(route)), len(route))
                self.assertTrue(set(model.route_links(source, destination)) <= legal_links)

    def test_xy_routes_horizontal_before_vertical(self) -> None:
        self.assertEqual(model.route_xy(0, 7), (0, 1, 2, 3, 7))
        self.assertEqual(model.route_xy(7, 0), (7, 6, 5, 4, 0))
        self.assertEqual(model.route_xy(1, 6), (1, 2, 6))
        self.assertEqual(model.route_xy(6, 1), (6, 5, 1))

    def test_middle_bisection_has_two_links_per_direction(self) -> None:
        east_links = {
            model.DirectedLink(model.pod_id(1, row), model.pod_id(2, row))
            for row in range(model.ROWS)
        }
        west_links = {
            model.DirectedLink(model.pod_id(2, row), model.pod_id(1, row))
            for row in range(model.ROWS)
        }
        self.assertTrue(east_links <= model.directed_links())
        self.assertTrue(west_links <= model.directed_links())
        self.assertEqual(len(east_links), 2)
        self.assertEqual(len(west_links), 2)

    def test_uniform_all_to_all_load_is_directionally_symmetric(self) -> None:
        flows = [
            model.TrafficFlow(source, destination, 128)
            for source in range(model.PODS)
            for destination in range(model.PODS)
            if source != destination
        ]
        loads = model.accumulate_link_bytes(flows)
        for link, payload_bytes in loads.items():
            reverse = model.DirectedLink(link.destination, link.source)
            self.assertEqual(payload_bytes, loads[reverse])

    def test_hotspot_and_transpose_patterns_are_fully_accounted(self) -> None:
        patterns = (
            model.hotspot_flows(0, 4096),
            model.hotspot_flows(7, 4096),
            model.transpose_flows(4096),
        )
        for flows in patterns:
            loads = model.accumulate_link_bytes(flows)
            expected_link_bytes = sum(
                flow.payload_bytes * len(model.route_links(
                    flow.source, flow.destination))
                for flow in flows
            )
            self.assertEqual(sum(loads.values()), expected_link_bytes)
            self.assertTrue(all(payload >= 0 for payload in loads.values()))

    def test_seeded_uniform_random_traffic_is_reproducible(self) -> None:
        first = model.uniform_random_flows(4096, 128, 0x4E4F43)
        second = model.uniform_random_flows(4096, 128, 0x4E4F43)
        different = model.uniform_random_flows(4096, 128, 0x4E4F44)
        self.assertEqual(first, second)
        self.assertNotEqual(first, different)
        self.assertTrue(all(flow.source != flow.destination for flow in first))
        loads = model.accumulate_link_bytes(first)
        self.assertTrue(all(link in model.directed_links() for link in loads))

    def test_invalid_identity_and_payload_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            model.route_xy(-1, 0)
        with self.assertRaises(ValueError):
            model.route_xy(0, model.PODS)
        with self.assertRaises(ValueError):
            model.accumulate_link_bytes([model.TrafficFlow(0, 1, -1)])
        with self.assertRaises(ValueError):
            model.hotspot_flows(model.PODS, 128)
        with self.assertRaises(ValueError):
            model.uniform_random_flows(-1, 128, 0)


if __name__ == "__main__":
    unittest.main()
