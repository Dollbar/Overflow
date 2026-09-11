"""C section 4: registered reference controller, not a DVFS controller."""

import unittest

try:
    from model.ualink.upli_connection import ConnectionSignals, UpliConnection
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_connection":
        raise
    ConnectionSignals = UpliConnection = None


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliConnection, "UPLI connection model not implemented")

    def start(self, **kwargs):
        controller = UpliConnection(**kwargs)
        controller.step(reset_n=False, orig_ready=False, comp_ready=False)
        controller.step(reset_n=True, orig_ready=True, comp_ready=True)
        return controller

    def test_reset_must_be_observed_before_connection(self):
        with self.assertRaises(ValueError):
            UpliConnection().step(reset_n=True, orig_ready=True, comp_ready=True)

    def test_deassertion_edge_is_idle_then_registered_requests_and_acks(self):
        controller = UpliConnection()
        controller.step(reset_n=False, orig_ready=True, comp_ready=True)
        self.assertEqual(controller.step(reset_n=True, orig_ready=True, comp_ready=True),
                         ConnectionSignals(False, False, False, False))
        self.assertEqual(controller.step(reset_n=True, orig_ready=True, comp_ready=True),
                         ConnectionSignals(True, False, True, False))
        self.assertTrue(controller.step(reset_n=True, orig_ready=True, comp_ready=True).beats_enabled)

    def test_originator_requests_without_waiting_for_completer(self):
        controller = self.start()
        state = controller.step(reset_n=True, orig_ready=True, comp_ready=False)
        self.assertEqual(state, ConnectionSignals(True, False, False, False))

    def test_originator_connected_first_allows_only_response_credit_direction(self):
        controller = self.start()
        controller.step(reset_n=True, orig_ready=True, comp_ready=False)
        state = controller.step(reset_n=True, orig_ready=True, comp_ready=True)
        self.assertTrue(state.orig_connected)
        self.assertFalse(state.comp_connected)
        self.assertFalse(state.beats_enabled)

    def test_completer_connected_first_is_supported(self):
        controller = self.start()
        controller.step(reset_n=True, orig_ready=False, comp_ready=True)
        state = controller.step(reset_n=True, orig_ready=True, comp_ready=True)
        self.assertFalse(state.orig_connected)
        self.assertTrue(state.comp_connected)

    def test_completer_can_wait_for_originator_connection(self):
        controller = self.start(completer_waits=True)
        self.assertEqual(controller.step(True, True, True), ConnectionSignals(True, False, False, False))
        self.assertEqual(controller.step(True, True, True), ConnectionSignals(True, True, False, False))
        self.assertEqual(controller.step(True, True, True), ConnectionSignals(True, True, True, False))
        self.assertTrue(controller.step(True, True, True).beats_enabled)

    def test_asserted_controls_stay_high_until_reset(self):
        controller = self.start()
        controller.step(True, True, True)
        controller.step(True, True, True)
        self.assertTrue(controller.step(True, False, False).beats_enabled)
        self.assertEqual(controller.step(False, True, True), ConnectionSignals(False, False, False, False))
        self.assertEqual(controller.step(True, True, True), ConnectionSignals(False, False, False, False))

    def test_minimum_reset_hold_is_checked_without_advancing_on_error(self):
        controller = UpliConnection(min_reset_cycles=3)
        controller.step(False, False, False)
        with self.assertRaises(ValueError):
            controller.step(True, True, True)
        controller.step(False, False, False)
        controller.step(False, False, False)
        self.assertFalse(controller.step(True, True, True).beats_enabled)
        for value in (0, -1, True, 1.0):
            with self.subTest(value=value), self.assertRaises((TypeError, ValueError)):
                UpliConnection(min_reset_cycles=value)

    def test_separate_station_controllers_do_not_share_state(self):
        first, second = self.start(), self.start()
        first.step(True, True, True)
        self.assertTrue(first.step(True, True, True).beats_enabled)
        self.assertFalse(second.step(True, False, False).beats_enabled)


if __name__ == "__main__":
    unittest.main()
