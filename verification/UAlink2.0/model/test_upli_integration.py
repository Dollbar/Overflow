"""Cycle composition of connection, credit init and TDM, not a TL transaction."""

import unittest

from model.ualink.upli_connection import UpliConnection
from model.ualink.upli_credit import Account, Beat, CreditReturn, CreditInitMonitor, UpliCreditLedger
from model.ualink.upli_tdm import UpliTdm


class UpliIntegrationTests(unittest.TestCase):
    def test_registered_handshake_early_credit_init_then_tdm_request_and_reset(self):
        connection = UpliConnection()
        account = Account(1, "req", 2)
        ledger = UpliCreditLedger({account: 2}, num_ports=2)
        init = CreditInitMonitor(2)
        tdm = UpliTdm(2)
        slot = (1, "req")

        def edge(reset_n=True, orig_ready=False, comp_ready=False, grants=(), beats=(), done=()):
            # All consumers use the SAME pre-edge control snapshot, not newly computed ACK.
            ledger.step(connection.signals, returns=grants, beats=beats, init_done=done, reset=not reset_n)
            init.step(credit_slots=tuple((g.port, g.channel) for g in grants),
                      done_slots=done, reset=not reset_n)
            tdm.step(tuple((b.channel, b.port) for b in beats), reset=not reset_n)
            return connection.step(reset_n, orig_ready, comp_ready)

        edge(reset_n=False)
        edge(comp_ready=True)
        edge(comp_ready=True)  # CompReq asserted after this edge.
        state = edge(orig_ready=True, comp_ready=True)  # OrigAck and OrigReq now assert.
        self.assertTrue(state.comp_connected)
        self.assertFalse(state.orig_connected)
        state = edge(orig_ready=True, comp_ready=True, grants=(CreditReturn(1, "req", 2, False, 1),))
        self.assertTrue(state.beats_enabled)
        self.assertEqual(ledger.balance(account), 2)
        edge(orig_ready=True, comp_ready=True, done=(slot,))
        self.assertFalse(ledger.initialized(*slot))
        edge(orig_ready=True, comp_ready=True, done=(slot,))
        edge(orig_ready=True, comp_ready=True, done=(slot,), beats=(Beat(1, "req", 2),))
        edge(orig_ready=True, comp_ready=True, done=(slot,))  # Port0 TDM idle.
        edge(orig_ready=True, comp_ready=True, done=(slot,), beats=(Beat(1, "req", 2),))
        self.assertEqual(ledger.balance(account), 0)
        edge(reset_n=False)
        self.assertFalse(ledger.initialized(*slot))
        self.assertFalse(connection.signals.beats_enabled)
        self.assertEqual(ledger.balance(account), 0)


if __name__ == "__main__":
    unittest.main()
