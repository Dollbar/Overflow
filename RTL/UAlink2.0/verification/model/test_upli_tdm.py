"""C 2.5: three phase groups, including shared request/originator-data phase."""

import unittest

try:
    from model.ualink.upli_tdm import UpliTdm
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_tdm":
        raise
    UpliTdm = None


class TdmTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliTdm, "UPLI TDM model not implemented")

    def test_nonzero_first_request_and_independent_response_phases(self):
        tdm = UpliTdm(4)
        tdm.step((("req", 2), ("orig_data", 2), ("rd_rsp", 0), ("wr_rsp", 3)))
        tdm.step((("orig_data", 3), ("rd_rsp", 1), ("wr_rsp", 0)))
        tdm.step()
        tdm.step((("req", 1), ("rd_rsp", 3), ("wr_rsp", 2)))

    def test_data_cannot_establish_phase_without_request(self):
        with self.assertRaises(ValueError):
            UpliTdm(4).step((("orig_data", 0),))

    def test_data_and_request_must_share_phase_regardless_of_event_order(self):
        tdm = UpliTdm(4)
        tdm.step((("orig_data", 2), ("req", 2)))
        with self.assertRaises(ValueError):
            tdm.step((("orig_data", 0),))
        tdm.step((("orig_data", 3),))

    def test_duplicate_channel_or_unused_port_does_not_update_phase(self):
        tdm = UpliTdm(2)
        for beats in ((("req", 2),), (("req", 0), ("req", 1)), (("unknown", 0),), (("req", True),)):
            with self.subTest(beats=beats), self.assertRaises((TypeError, ValueError)):
                tdm.step(beats)
        tdm.step((("req", 1),))
        tdm.step((("req", 0),))

    def test_reset_forgets_old_phases_and_ignores_inflight_events(self):
        tdm = UpliTdm(4)
        tdm.step((("req", 1),))
        tdm.step((("req", 99),), reset=True)
        tdm.step()
        tdm.step((("req", 3),))
        tdm.step((("req", 0),))

    def test_single_port_and_invalid_bifurcation_sizes(self):
        tdm = UpliTdm(1)
        for _ in range(8):
            tdm.step((("req", 0), ("orig_data", 0), ("rd_rsp", 0), ("wr_rsp", 0)))
        for ports in (0, 3, 8, True, 2.0):
            with self.subTest(ports=ports), self.assertRaises((TypeError, ValueError)):
                UpliTdm(ports)


if __name__ == "__main__":
    unittest.main()
