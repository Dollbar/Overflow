"""Cycle-contract tests for real reset commit, queue and timeout boundaries.

Run: python3 -m unittest verification.model.test_uart_reset_control -v
Outputs: cycle-model checks. Next: compile RTL and execute every real timer edge.
"""
import unittest
try:
    from model.ualink.uart_reset_control import UARTResetControl
except ModuleNotFoundError:
    UARTResetControl=None


class UARTResetControlTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UARTResetControl,'UART reset cycle model is missing')

    def active(self,period=1_000_000_000,depth=4):
        m=UARTResetControl(clock_period_ps=period,response_depth=depth)
        m.tick(reset=True);return m

    def request(self,m):
        self.assertTrue(m.tick(local_request=True).local_start)
        for index in range(40):
            out=m.tick(tx_take=True)
            self.assertEqual((out.tx_kind,out.tx_word,out.noops_left),(1,0,40-index))
            self.assertTrue(out.block_messages and out.stream_reset)
        out=m.tick(tx_take=True);self.assertEqual((out.tx_kind,out.tx_word),(2,0x184))
        self.assertTrue(m.observe().waiting);self.assertFalse(m.observe().block_messages)

    def test_local_start_blocks_same_edge_then_counts_real_takes(self):
        m=self.active();self.assertTrue(m.observe().local_ready)
        out=m.tick(local_request=True,local_all=True)
        self.assertTrue(out.local_start and out.stream_reset and out.block_messages)
        self.assertFalse(out.tx_pending)
        m.idle(25)
        for index in range(40):
            out=m.tick(tx_take=True);self.assertEqual((out.tx_word,out.noops_left),(0,40-index))
        self.assertEqual(m.tick(tx_take=True).tx_word,0x1184)
        self.assertTrue(m.observe().waiting)

    def test_real_timeout_counts_for_both_declared_periods(self):
        for period,cycles in ((640,15_625_000),(6400,1_562_500),(1_000_000_000,10),(999_999_999,11)):
            with self.subTest(period=period):
                m=self.active(period);self.request(m);m.idle(cycles-1)
                out=m.observe();self.assertTrue(out.waiting and out.retry and out.block_messages)
                self.assertFalse(out.tx_pending)
                m.tick();out=m.observe()
                self.assertEqual((out.tx_kind,out.noops_left),(1,40));self.assertFalse(out.retry)

    def test_success_wins_at_timeout_and_early_success_is_ignored(self):
        m=self.active();m.tick(local_request=True)
        for _ in range(40):m.tick(tx_take=True)
        out=m.tick(tx_take=True,rx_response=True,response_status=0)
        self.assertFalse(out.local_done);self.assertTrue(m.observe().waiting)
        m.idle(9)
        out=m.tick(rx_response=True,response_status=0)
        self.assertTrue(out.local_done);self.assertFalse(out.retry)
        self.assertFalse(m.observe().stream_reset or m.observe().waiting)
        self.request(m);m.idle(9)
        self.assertTrue(m.tick(rx_response=True,response_status=7).retry)
        self.assertEqual(m.observe().tx_kind,1)

    def test_full_queue_can_replace_committed_head_without_scope_loss(self):
        for depth in (1,3,4,16):
            m=self.active(depth=depth)
            for index in range(depth):
                out=m.tick(rx_request=True,request_all=bool(index%2))
                self.assertTrue(out.stream_reset);self.assertFalse(out.error)
            self.assertEqual(m.observe().response_count,depth)
            for index in range(depth):
                out=m.tick(tx_take=True,rx_request=True,request_all=True)
                self.assertTrue(out.reply_done);self.assertFalse(out.error)
                self.assertEqual(out.tx_word,0x11C4 if index%2 else 0x1C4)
                self.assertEqual(m.observe().response_count,depth)
            for _ in range(depth):self.assertEqual(m.tick(tx_take=True).tx_word,0x11C4)
            self.assertFalse(m.observe().stream_reset or m.observe().fault)

    def test_overflow_latches_fault_and_global_reset_clears_it(self):
        m=self.active(depth=1);m.tick(rx_request=True)
        out=m.tick(rx_request=True,request_all=True)
        self.assertTrue(out.error);self.assertFalse(out.fault)
        out=m.observe();self.assertTrue(out.fault and out.stream_reset and out.block_messages)
        self.assertFalse(out.local_ready or out.tx_pending or out.waiting)
        out=m.tick(local_request=True,rx_response=True,rx_request=True,tx_take=True)
        self.assertFalse(out.error or out.local_done or out.reply_done)
        self.assertTrue(m.observe().fault)
        m.tick(reset=True,rx_request=True,local_request=True,tx_take=True)
        self.assertFalse(m.observe().fault or m.observe().stream_reset)

    def test_invalid_take_and_local_start_cancelled_offer_are_diagnosed(self):
        m=self.active();self.assertTrue(m.tick(tx_take=True).error);self.assertTrue(m.observe().fault)
        m.tick(reset=True);m.tick(rx_request=True)
        out=m.tick(local_request=True,tx_take=True)
        self.assertTrue(out.local_start and out.error);self.assertFalse(out.tx_pending)
        self.assertTrue(m.observe().fault)

    def test_local_and_peer_ownership_stays_independent(self):
        m=self.active();m.tick(rx_request=True,request_all=True)
        m.tick(local_request=True)
        for _ in range(41):m.tick(tx_take=True)
        self.assertEqual(m.tick(tx_take=True).tx_word,0x11C4)
        self.assertTrue(m.observe().stream_reset and m.observe().waiting)
        m.tick(rx_request=True)
        self.assertTrue(m.tick(rx_response=True,response_status=0).local_done)
        self.assertTrue(m.observe().stream_reset);self.assertFalse(m.observe().waiting)
        self.assertTrue(m.tick(tx_take=True).reply_done);self.assertFalse(m.observe().stream_reset)

    def test_bulk_idle_rejects_a_hidden_transition(self):
        m=self.active();self.request(m)
        with self.assertRaises(ValueError):m.idle(10)
        self.assertFalse(m.observe().retry)
        m.idle(9);self.assertTrue(m.observe().retry)
        m.tick();self.assertEqual(m.observe().noops_left,40)

    def test_invalid_configuration_and_events_leave_state_intact(self):
        for value in (True,0,-1,1.5,1_000_000_001):
            with self.assertRaises(ValueError):UARTResetControl(clock_period_ps=value)
        for value in (True,0,-1,1.5,17):
            with self.assertRaises(ValueError):UARTResetControl(response_depth=value)
        m=self.active();m.tick(local_request=True);before=m.observe()
        for value in (0,1,None,'yes'):
            with self.assertRaises(ValueError):m.tick(rx_request=value)
        for value in (True,-1,8,None):
            with self.assertRaises(ValueError):m.tick(response_status=value)
        for value in (True,0,-1,1.5):
            with self.assertRaises(ValueError):m.idle(value)
        self.assertEqual(m.observe(),before)


if __name__=='__main__':unittest.main()
