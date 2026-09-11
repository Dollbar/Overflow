"""WP01: count, index and Pod arithmetic, not hardware/profile acceptance."""

import unittest

try:
    from model.ualink.configuration import StationLayout, validate_pod
except ModuleNotFoundError as error:
    if error.name != "model.ualink.configuration":
        raise
    StationLayout = None
    validate_pod = None


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(StationLayout, "WP01 configuration model is not implemented")

    def test_three_station_modes_preserve_physical_lane_capacity(self):
        # Catches the error of multiplying physical lanes by bifurcation.
        for mode, ports, lanes_per_port in (("x4", 3, 4), ("2x2", 6, 2), ("4x1", 12, 1)):
            with self.subTest(mode=mode):
                layout = StationLayout(3, mode)
                self.assertEqual(layout.num_lanes, 12)
                self.assertEqual(layout.num_ports, ports)
                self.assertEqual(layout.lanes_per_port, lanes_per_port)

    def test_station_count_rejects_non_positive_and_non_integer_inputs(self):
        # bool is a Python int subclass, but is not an accepted hardware count.
        for count in (0, -1, True, False, 1.0, "4", None):
            with self.subTest(count=count), self.assertRaises((TypeError, ValueError)):
                StationLayout(count, "x4")

    def test_unknown_bifurcation_is_not_silently_normalized(self):
        for mode in ("x8", "x2", "X4", "", None, []):
            with self.subTest(mode=mode), self.assertRaises((TypeError, ValueError)):
                StationLayout(1, mode)

    def test_all_count_legal_configurations_and_first_illegal_boundary(self):
        # R045 limits configured port counts, not station or PortNum bit width.
        for mode, maximum, scale in (("x4", 1024, 1), ("2x2", 512, 2), ("4x1", 256, 4)):
            for count in range(1, maximum + 1):
                with self.subTest(mode=mode, count=count):
                    self.assertEqual(StationLayout(count, mode).num_ports, count * scale)
            with self.subTest(mode=mode, overflow=True), self.assertRaises(ValueError):
                StationLayout(maximum + 1, mode)

    def test_non_power_of_two_station_indices_do_not_alias(self):
        layout = StationLayout(3, "2x2")
        self.assertEqual(layout.station_index_width, 2)
        self.assertEqual(layout.split_port_index(0), (0, 0))
        self.assertEqual(layout.split_port_index(5), (2, 1))
        with self.assertRaises(ValueError):
            layout.split_port_index(6)

    def test_single_station_has_no_zero_width_rtl_index(self):
        self.assertEqual(StationLayout(1, "x4").station_index_width, 1)
        self.assertEqual(StationLayout(16, "x4").station_index_width, 4)
        self.assertEqual(StationLayout(17, "x4").station_index_width, 5)

    def test_port_index_rejects_negative_boolean_and_non_integer_inputs(self):
        for index in (-1, True, 0.5, "0"):
            with self.subTest(index=index), self.assertRaises((TypeError, ValueError)):
                StationLayout(3, "4x1").split_port_index(index)

    def test_lane_assignment_respects_station_and_port_boundaries(self):
        cases = (("x4", 3, (0, 0, 3)), ("2x2", 2, (0, 1, 0)),
                 ("2x2", 11, (2, 1, 1)), ("4x1", 11, (2, 3, 0)))
        for mode, index, expected in cases:
            with self.subTest(mode=mode, index=index):
                self.assertEqual(StationLayout(3, mode).lane_assignment(index), expected)
        for index in (-1, 12, True, 0.0):
            with self.subTest(index=index), self.assertRaises((TypeError, ValueError)):
                StationLayout(3, "2x2").lane_assignment(index)

    def test_configuration_is_immutable_to_prevent_unvalidated_live_change(self):
        layout = StationLayout(1, "x4")
        with self.assertRaises(AttributeError):
            layout.bifurcation = "4x1"

    def test_pod_accepts_different_accelerator_and_physical_switch_sizes(self):
        # C §2.4 does not require identical station counts for all device roles.
        validate_pod([StationLayout(1, "x4")] * 3,
                     [StationLayout(3, "x4"), StationLayout(4, "x4")])

    def test_pod_rejects_mixed_bifurcation(self):
        with self.assertRaises(ValueError):
            validate_pod([StationLayout(1, "x4")], [StationLayout(1, "4x1")])

    def test_pod_rejects_unequal_accelerator_ports(self):
        with self.assertRaises(ValueError):
            validate_pod([StationLayout(1, "x4"), StationLayout(2, "x4")],
                         [StationLayout(2, "x4")])

    def test_pod_rejects_switch_with_too_few_ports(self):
        with self.assertRaises(ValueError):
            validate_pod([StationLayout(1, "x4")] * 3, [StationLayout(2, "x4")])

    def test_managed_pod_device_count_boundaries(self):
        validate_pod([StationLayout(1, "x4")] * 1024, [StationLayout(1024, "x4")])
        validate_pod([StationLayout(1, "x4")], [StationLayout(1, "x4")] * 1024)
        for accs, switches in ((1025, 1), (1, 1025)):
            with self.subTest(accs=accs, switches=switches), self.assertRaises(ValueError):
                validate_pod([StationLayout(1, "x4")] * accs,
                             [StationLayout(1024, "x4")] * switches)

    def test_empty_or_malformed_pod_is_not_accepted_by_this_fixture(self):
        for accs, switches in (([], [StationLayout(1, "x4")]),
                              ([StationLayout(1, "x4")], []),
                              (["x4"], [StationLayout(1, "x4")])):
            with self.subTest(accs=accs, switches=switches), self.assertRaises((TypeError, ValueError)):
                validate_pod(accs, switches)


if __name__ == "__main__":
    unittest.main()
