"""Cycle boundaries independently composed from the Basic event reference.
Run: python3 -m unittest verification.model.test_dl_basic_control -v
Outputs: cycle contract checks; next: compare all native RTL outputs per edge.
"""
import unittest
try:
    from model.ualink.dl_basic_control import DLBasicControl
except ModuleNotFoundError:
    DLBasicControl=None


class DLBasicControlTests(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(DLBasicControl,'Basic cycle reference is missing')

    def test_request_ack_same_commit_edge_is_early(self):
        c=DLBasicControl();c.tick(local_valid=True,local_kind=4,local_rate=3125)
        o=c.tick(source_take=2,rx_valid=True,rx_word=0x1100)
        self.assertTrue(o.local_commit and o.rx_unmatched_ack and o.error)
        self.assertFalse(o.local_done);self.assertTrue(c.observe().local_waiting)
        self.assertTrue(c.tick(rx_valid=True,rx_word=0x1100).local_done)

    def test_new_remote_precedes_same_edge_local_of_same_type(self):
        c=DLBasicControl();o=c.tick(local_valid=True,local_kind=6,rx_valid=True,rx_word=0x180,port_valid=True,port=4)
        self.assertTrue(o.local_start and o.rx_request)
        self.assertEqual(c.observe().source_words,0x80041180<<96)
        self.assertTrue(c.tick(source_take=8).reply_done)
        self.assertEqual(c.observe().source_words,0x80040180<<96)

    def test_local_head_survives_new_remote_and_configuration_changes(self):
        c=DLBasicControl();c.tick(local_valid=True,local_kind=5,device_valid=True,device_id=17,device_type=1)
        c.tick(rx_valid=True,rx_word=0x140,device_valid=True,device_id=22,device_type=0)
        self.assertEqual(c.observe(device_id=99).source_words,0xA0110140<<64)
        self.assertTrue(c.tick(source_take=4).local_commit)
        self.assertEqual(c.observe().source_words,0x80161140<<64)

    def test_same_edge_reply_releases_remote_slot(self):
        c=DLBasicControl();c.tick(rx_valid=True,rx_word=0x180)
        o=c.tick(source_take=8,rx_valid=True,rx_word=0x140)
        self.assertTrue(o.reply_done and o.rx_request);self.assertFalse(o.error)
        self.assertEqual(c.observe().source_pending,4)

    def test_matching_ack_does_not_reuse_local_slot_same_edge(self):
        c=DLBasicControl();c.tick(local_valid=True,local_kind=6);c.tick(source_take=8)
        o=c.tick(rx_valid=True,rx_word=0x1180,local_valid=True,local_kind=5)
        self.assertTrue(o.local_done);self.assertFalse(o.local_start or o.local_ready)
        self.assertTrue(c.tick(local_valid=True,local_kind=5).local_start)

    def test_deadline_uses_actual_edges_and_saturates(self):
        for period in (640,6400,1_000_000,1_000_001):
            c=DLBasicControl(period);c.tick(rx_valid=True,rx_word=0x180)
            allowed=1_000_000//period
            for _ in range(max(0,allowed-1)):
                self.assertFalse(c.tick().deadline_miss)
            if allowed:
                self.assertFalse(c.tick(source_take=8).deadline_miss)
                self.assertFalse(c.observe().deadline_fault)
            else:self.assertTrue(c.tick(source_take=8).deadline_miss)
            c=DLBasicControl(period);c.tick(rx_valid=True,rx_word=0x180)
            for _ in range(allowed):self.assertFalse(c.tick().deadline_miss)
            self.assertTrue(c.tick().deadline_miss)
            for _ in range(5):self.assertFalse(c.tick().deadline_miss)
            self.assertTrue(c.observe().remote_pending and c.observe().deadline_fault)

    def test_invalid_multiple_take_preserves_all_ownership(self):
        c=DLBasicControl();c.tick(local_valid=True,local_kind=5,rx_valid=True,rx_word=0x180)
        o=c.tick(source_take=12)
        self.assertTrue(o.error);self.assertFalse(o.local_commit or o.reply_done)
        self.assertEqual(c.observe().source_pending,12);self.assertTrue(c.observe().protocol_fault)
        self.assertTrue(c.tick(source_take=1).error)

    def test_pacing_unready_blocks_reply_and_same_type_local(self):
        c=DLBasicControl();c.tick(rx_valid=True,rx_word=0x0C350100)
        c.tick(local_valid=True,local_kind=4,local_rate=31250)
        self.assertEqual(c.observe(tx_limit_valid=True,tx_limit=3126).source_pending,0)
        self.assertEqual(c.observe(tx_limit_valid=True,tx_limit=3125).source_words,0x1100<<32)
        self.assertEqual(c.observe().source_pending,0)
        self.assertTrue(c.tick(source_take=2,tx_limit_valid=True,tx_limit=3125).reply_done)
        self.assertEqual(c.observe().source_words,0x7A120100<<32)

    def test_reset_and_invalid_configuration_guards(self):
        c=DLBasicControl();c.tick(local_valid=True,local_kind=6,rx_valid=True,rx_word=0x140)
        o=c.tick(reset=True,source_take=15,rx_valid=True,rx_word=0x180,local_valid=True,local_kind=6)
        self.assertFalse(o.local_pending or o.remote_pending or o.error or o.source_pending)
        self.assertFalse(c.observe().local_pending or c.observe().remote_pending)
        self.assertTrue(c.tick(local_valid=True,local_kind=2).error)
        for p in (0,1_000_000_001,True):
            with self.assertRaises(ValueError):DLBasicControl(p)


if __name__=='__main__':unittest.main()
