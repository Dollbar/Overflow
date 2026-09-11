"""Passive normal-burst legality checks, including deliberately corrupt traces."""

import unittest

from model.ualink.upli_burst import BurstData, BurstRequest

try:
    from model.ualink.upli_burst_monitor import UpliBurstMonitor
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_burst_monitor":
        raise
    UpliBurstMonitor = None


class BurstMonitorTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliBurstMonitor, "UPLI burst passive monitor not implemented")

    def test_all_lengths_accept_independent_legal_per_beat_pool_choices(self):
        for ports in (1, 2, 4):
            for port in range(ports):
                for encoded, count in ((0, 1), (1, 2), (2, 3), (3, 4)):
                    monitor = UpliBurstMonitor(ports)
                    # The passive wire monitor must not validate the private allocation plan.
                    req = BurstRequest(port, 3, False, encoded)
                    for cycle in range((count - 1) * ports + 1):
                        offset = cycle // ports
                        data = BurstData(port, 3, offset % 2 == 0, offset, offset == count - 1) if cycle % ports == 0 else None
                        monitor.step(request=req if cycle == 0 else None, data=data)
                    monitor.step()

    def test_missing_first_data_is_rejected_without_establishing_phase(self):
        monitor = UpliBurstMonitor(4)
        with self.assertRaises(ValueError):
            monitor.step(BurstRequest(2, 0, False, 0))
        monitor.step(BurstRequest(3, 0, False, 0), BurstData(3, 0, False, 0, True))
        monitor.step(BurstRequest(0, 1))

    def test_due_slot_cannot_be_skipped_and_bad_step_does_not_advance_time(self):
        monitor = UpliBurstMonitor(4)
        monitor.step(BurstRequest(2, 1, False, 1), BurstData(2, 1, False, 0, False))
        for _ in range(3):
            monitor.step()
        with self.assertRaises(ValueError):
            monitor.step()
        monitor.step(data=BurstData(2, 1, True, 1, True))
        monitor.step()

    def test_wrong_offset_last_or_vc_cannot_replace_expected_data(self):
        bad = (BurstData(0, 2, False, 0, False), BurstData(0, 2, False, 2, True),
               BurstData(0, 2, False, 1, True), BurstData(0, 1, False, 1, False))
        for corrupted in bad:
            monitor = UpliBurstMonitor(1)
            monitor.step(BurstRequest(0, 2, False, 2), BurstData(0, 2, False, 0, False))
            with self.subTest(corrupted=corrupted), self.assertRaises(ValueError):
                monitor.step(data=corrupted)
            monitor.step(data=BurstData(0, 2, True, 1, False))
            monitor.step(data=BurstData(0, 2, False, 2, True))

    def test_last_required_exactly_on_first_or_final_beat(self):
        for encoded, wrong_last in ((0, False), (1, True), (2, True), (3, True)):
            monitor = UpliBurstMonitor(1)
            with self.assertRaises(ValueError):
                monitor.step(BurstRequest(0, 0, False, encoded), BurstData(0, 0, False, 0, wrong_last))
        monitor = UpliBurstMonitor(1)
        monitor.step(BurstRequest(0, 0, False, 1), BurstData(0, 0, False, 0, False))
        with self.assertRaises(ValueError):
            monitor.step(data=BurstData(0, 0, False, 1, False))
        monitor.step(data=BurstData(0, 0, False, 1, True))
        with self.assertRaises(ValueError):
            monitor.step(data=BurstData(0, 0, False, 2, True))

    def test_unassociated_data_and_first_beat_port_mismatch_are_rejected(self):
        for request in (None, BurstRequest(0, 0), BurstRequest(1, 0, False, 0)):
            monitor = UpliBurstMonitor(2)
            with self.subTest(request=request), self.assertRaises(ValueError):
                monitor.step(request, BurstData(0, 0, False, 0, True))

    def test_write_cannot_overlap_old_last_but_read_may_overlap_old_data(self):
        monitor = UpliBurstMonitor(1)
        monitor.step(BurstRequest(0, 2, False, 1), BurstData(0, 2, False, 0, False))
        with self.assertRaises(ValueError):
            monitor.step(BurstRequest(0, 1, False, 0), BurstData(0, 2, False, 1, True))
        monitor.step(BurstRequest(0, 1), BurstData(0, 2, True, 1, True))
        monitor.step(BurstRequest(0, 1, False, 0), BurstData(0, 1, False, 0, True))

    def test_independent_port_deadlines_allow_interleaved_bursts(self):
        monitor = UpliBurstMonitor(2)
        monitor.step(BurstRequest(1, 1, False, 2), BurstData(1, 1, False, 0, False))
        monitor.step(BurstRequest(0, 2, False, 1), BurstData(0, 2, True, 0, False))
        monitor.step(data=BurstData(1, 1, True, 1, False))
        monitor.step(data=BurstData(0, 2, False, 1, True))
        monitor.step(data=BurstData(1, 1, False, 2, True))

    def test_data_cannot_arrive_early_in_another_ports_slot(self):
        monitor = UpliBurstMonitor(4)
        monitor.step(BurstRequest(3, 0, False, 1), BurstData(3, 0, False, 0, False))
        with self.assertRaises(ValueError):
            monitor.step(data=BurstData(3, 0, False, 1, True))
        for _ in range(3):
            monitor.step()
        monitor.step(data=BurstData(3, 0, False, 1, True))

    def test_idle_cycles_preserve_established_request_tdm(self):
        monitor = UpliBurstMonitor(4)
        monitor.step(BurstRequest(1, 0))
        monitor.step()
        with self.assertRaises(ValueError):
            monitor.step(BurstRequest(2, 0))
        monitor.step(BurstRequest(3, 0))

    def test_reset_flushes_pending_deadlines_and_ignores_business(self):
        monitor = UpliBurstMonitor(4)
        monitor.step(BurstRequest(0, 0, False, 3), BurstData(0, 0, False, 0, False))
        monitor.step(request=object(), data=object(), reset=True)
        for _ in range(8):
            monitor.step()
        monitor.step(BurstRequest(3, 1, False, 0), BurstData(3, 1, True, 0, True))

    def test_bad_signal_widths_and_types_are_not_silently_truncated(self):
        for ports in (0, 3, True):
            with self.assertRaises((TypeError, ValueError)):
                UpliBurstMonitor(ports)
        monitor = UpliBurstMonitor(1)
        for request in (object(), BurstRequest(1, 0), BurstRequest(0, True),
                        BurstRequest(0, 0, 1), BurstRequest(0, 0, False, True), BurstRequest(0, 0, False, 4)):
            with self.subTest(request=request), self.assertRaises((TypeError, ValueError)):
                monitor.step(request)
        for data in (object(), BurstData(0, 0, 1, 0, True), BurstData(0, 0, False, True, True),
                     BurstData(0, 0, False, 4, True), BurstData(0, 0, False, 0, 1), BurstData(0, 4, False, 0, True)):
            with self.subTest(data=data), self.assertRaises((TypeError, ValueError)):
                monitor.step(BurstRequest(0, 0, False, 0), data)
        with self.assertRaises(TypeError):
            monitor.step(reset=1)
        monitor.step(BurstRequest(0, 0, False, 0), BurstData(0, 0, False, 0, True))


if __name__ == "__main__":
    unittest.main()
