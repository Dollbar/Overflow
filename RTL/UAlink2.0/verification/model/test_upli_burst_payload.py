"""Staged payload ownership and credit accounting, independent literal data.

Run: python3 -m unittest verification.model.test_upli_burst_payload -v
Output: model test results; next: RTL wrapper/vector/TB, not protocol signoff.
"""
from dataclasses import FrozenInstanceError
from itertools import product
import unittest

from model.ualink.upli_burst import BurstRequest
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, CreditReturn

try:
    from model.ualink.upli_burst_payload import OrigDataPayload, StagedBurst, UpliBurstPayload
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_burst_payload":
        raise
    OrigDataPayload = StagedBurst = UpliBurstPayload = None


class BurstPayloadTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliBurstPayload, "complete staged payload model missing")
        self.connected = ConnectionSignals(True, True, True, True)
        self.words = (OrigDataPayload((1 << 511) | 0x11, 0x8000000000000001, False),
                      OrigDataPayload(0x22, 0, True),
                      OrigDataPayload((1 << 511) | 0x33, 0xAAAAAAAAAAAAAAAA, False),
                      OrigDataPayload(0x44, 0xFFFFFFFFFFFFFFFF, True))

    def initialized(self, ports=1, count=4):
        caps = {Account(p, ch, vc): count for p in range(ports)
                for ch in ("req", "orig_data") for vc in (None,0,1,2,3)}
        sender = UpliBurstPayload(caps, ports, request_width=96)
        for account in caps:
            sender.step(self.connected, returns=(CreditReturn(account.port, account.channel,
                        0 if account.vc is None else account.vc, account.vc is None, count-1),))
        slots = tuple((p,ch) for p in range(ports) for ch in ("req","orig_data"))
        sender.step(self.connected, init_done=slots)
        sender.step(self.connected, init_done=slots)
        return sender

    def test_first_beat_and_opaque_request_transfer_on_the_same_edge(self):
        sender = self.initialized()
        candidate = StagedBurst(BurstRequest(0,3,True,3,(False,True,False,True)), (1 << 95) | 0x1234, self.words)
        event = sender.step(self.connected, candidate)
        self.assertTrue(event.control.accepted)
        self.assertEqual(event.request_payload, (1 << 95) | 0x1234)
        self.assertEqual((event.data_payload.data,event.data_payload.byte_enable,event.data_payload.error),
                         ((1 << 511) | 0x11, 0x8000000000000001, False))
        self.assertEqual((event.control.data.port,event.control.data.vc,event.control.data.offset,event.control.data.last),
                         (0,3,0,False))
        for account,want in ((Account(0,"orig_data",3),(3,1,2)),(Account(0,"orig_data",None),(4,2,2))):
            self.assertEqual((sender.balance(account),sender.reserved(account),sender.available(account)),want)

    def test_changed_candidate_and_overlay_read_cannot_replace_accepted_tail(self):
        sender = self.initialized()
        write = StagedBurst(BurstRequest(0,3,False,3,(False,True,False,True)), 0x100, self.words)
        sender.step(self.connected, write)
        read = StagedBurst(BurstRequest(0,1,True),0xABC)
        event = sender.step(self.connected, read)
        self.assertTrue(event.control.accepted)
        self.assertEqual(event.request_payload,0xABC)
        self.assertEqual(event.data_payload,self.words[1])
        self.assertEqual((event.control.data.vc,event.control.data.pool,event.control.data.offset),(3,True,1))
        # A completely different write remains owned by its caller during the tail.
        other = StagedBurst(BurstRequest(0,0,True,0,(False,)),0xFFF,(self.words[0],))
        event = sender.step(self.connected, other)
        self.assertFalse(event.control.accepted)
        self.assertIsNone(event.request_payload)
        self.assertEqual(event.data_payload,self.words[2])
        event = sender.step(self.connected, other)
        self.assertFalse(event.control.accepted)
        self.assertEqual(event.data_payload,self.words[3])
        self.assertTrue(event.control.data.last)
        self.assertTrue(sender.step(self.connected,other).control.accepted)

    def test_each_port_keeps_its_own_remaining_data_and_metadata(self):
        sender = self.initialized(ports=4)
        a = StagedBurst(BurstRequest(3,1,False,2,(False,True,False)),0xAA,self.words[:3])
        b = StagedBurst(BurstRequest(0,2,True,1,(True,False)),0xBB,(self.words[3],self.words[0]))
        expected = {0:(3,0,self.words[0]),1:(0,0,self.words[3]),4:(3,1,self.words[1]),
                    5:(0,1,self.words[0]),8:(3,2,self.words[2])}
        for cycle in range(9):
            event = sender.step(self.connected,{0:a,1:b}.get(cycle))
            if cycle in expected:
                port,offset,payload = expected[cycle]
                self.assertEqual((event.control.data.port,event.control.data.offset,event.data_payload),
                                 (port,offset,payload))
            else:
                self.assertIsNone(event.control.data)
                self.assertIsNone(event.data_payload)

    def test_lengths_and_all_credit_patterns_deliver_exactly_the_declared_payload(self):
        for ports in (1,2,4):
            for encoded,count in ((0,1),(1,2),(2,3),(3,4)):
                for pattern in product((False,True),repeat=count):
                    with self.subTest(ports=ports,encoded=encoded,pattern=pattern):
                        sender = self.initialized(ports)
                        candidate = StagedBurst(BurstRequest(ports-1,2,False,encoded,pattern),0x555,self.words[:count])
                        seen = []
                        for cycle in range(count*ports+1):
                            event = sender.step(self.connected,candidate if cycle==0 else None)
                            if event.data_payload is not None:
                                seen.append(event.data_payload)
                                self.assertEqual(event.control.data.pool,pattern[len(seen)-1])
                                self.assertEqual(event.control.data.offset,len(seen)-1)
                                self.assertEqual(event.control.data.last,len(seen)==count)
                        self.assertEqual(tuple(seen),self.words[:count])
                        self.assertEqual(sender.reserved(Account(ports-1,"orig_data",2)),0)
                        self.assertEqual(sender.reserved(Account(ports-1,"orig_data",None)),0)

    def test_incomplete_or_mutable_payload_rejects_before_control_or_credit_change(self):
        sender = self.initialized()
        request = BurstRequest(0,0,False,2,(False,False,False))
        invalid = (object(), StagedBurst(request,1,self.words[:2]), StagedBurst(request,1,self.words),
                   StagedBurst(request,1,list(self.words[:3])),
                   StagedBurst(request,1,(self.words[0],object(),self.words[2])),
                   StagedBurst(BurstRequest(0,0),1,(self.words[0],)),
                   StagedBurst(request,-1,self.words[:3]), StagedBurst(request,1 << 96,self.words[:3]),
                   StagedBurst(request,True,self.words[:3]))
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises((TypeError,ValueError)):
                sender.step(self.connected,candidate)
            self.assertIsNone(sender.next_port)
            self.assertEqual(sender.balance(Account(0,"req",0)),4)
            self.assertEqual(sender.balance(Account(0,"orig_data",0)),4)

    def test_data_byte_enable_and_error_widths_are_validated_without_consuming_tail(self):
        sender = self.initialized()
        sender.step(self.connected,StagedBurst(BurstRequest(0,0,False,1,(False,False)),1,self.words[:2]))
        invalid = (OrigDataPayload(-1,0,False),OrigDataPayload(1 << 512,0,False),OrigDataPayload(True,0,False),
                   OrigDataPayload(0,-1,False),OrigDataPayload(0,1 << 64,False),OrigDataPayload(0,True,False),
                   OrigDataPayload(0,0,1))
        for data in invalid:
            with self.subTest(data=data), self.assertRaises((TypeError,ValueError)):
                sender.step(self.connected,StagedBurst(BurstRequest(0,1,False,0,(False,)),2,(data,)))
        self.assertEqual(sender.step(self.connected).data_payload,self.words[1])

    def test_bad_credit_edge_is_atomic_for_payload_control_and_banks(self):
        sender = self.initialized()
        sender.step(self.connected,StagedBurst(BurstRequest(0,0,False,2,(False,)*3),1,self.words[:3]))
        account = Account(0,"orig_data",0)
        self.assertEqual((sender.balance(account),sender.reserved(account)),(3,2))
        with self.assertRaises(ValueError):
            sender.step(self.connected,returns=(CreditReturn(0,"orig_data",0,False,4),))
        self.assertEqual((sender.balance(account),sender.reserved(account)),(3,2))
        event = sender.step(self.connected,returns=(CreditReturn(0,"orig_data",0,False,0),))
        self.assertEqual(event.data_payload,self.words[1])
        self.assertEqual((sender.balance(account),sender.reserved(account)),(3,1))
        self.assertEqual(sender.step(self.connected).data_payload,self.words[2])

    def test_reset_discards_payload_even_with_malformed_inputs_then_reinitializes(self):
        sender = self.initialized()
        sender.step(self.connected,StagedBurst(BurstRequest(0,0,False,3,(False,)*4),1,self.words))
        event = sender.step(None,object(),returns=(None,),init_done=(None,),reset=True)
        self.assertFalse(event.control.accepted)
        self.assertIsNone(event.request_payload)
        self.assertIsNone(event.data_payload)
        self.assertIsNone(sender.next_port)
        self.assertEqual(sender.balance(Account(0,"orig_data",0)),0)
        self.assertIsNone(sender.step(self.connected).data_payload)
        grants = (CreditReturn(0,"req",0,False,0),CreditReturn(0,"orig_data",0,False,0))
        sender.step(self.connected,returns=grants)
        slots = ((0,"req"),(0,"orig_data"))
        sender.step(self.connected,init_done=slots)
        sender.step(self.connected,init_done=slots)
        event = sender.step(self.connected,StagedBurst(BurstRequest(0,0,False,0,(False,)),0x222,(self.words[3],)))
        self.assertEqual(event.data_payload,self.words[3])
        self.assertEqual(event.control.data.offset,0)
        self.assertTrue(event.control.data.last)

    def test_read_class_carries_request_only_and_descriptors_are_immutable(self):
        sender = self.initialized()
        candidate = StagedBurst(BurstRequest(0,2),0)
        with self.assertRaises(FrozenInstanceError):
            candidate.request_payload = 1
        with self.assertRaises(FrozenInstanceError):
            self.words[0].data = 0
        event = sender.step(self.connected,candidate)
        self.assertEqual(event.request_payload,0)
        self.assertIsNone(event.data_payload)
        self.assertIsNone(event.control.data)

    def test_request_width_and_reset_type_reject_invalid_configuration(self):
        for width in (0,-1,True,1.5):
            with self.assertRaises((TypeError,ValueError)):
                UpliBurstPayload({},1,request_width=width)
        sender = self.initialized()
        with self.assertRaises(TypeError):
            sender.step(self.connected,reset=1)
        self.assertIsNone(sender.next_port)

    def test_arriving_credit_cannot_accept_or_capture_a_blocked_payload(self):
        req, data = Account(0,"req",0),Account(0,"orig_data",0)
        sender = UpliBurstPayload({req:1,data:1},1,request_width=96)
        slots = ((0,"req"),(0,"orig_data"))
        sender.step(self.connected,init_done=slots)
        sender.step(self.connected,init_done=slots)
        rejected = StagedBurst(BurstRequest(0,0,False,0,(False,)),0x111,(self.words[0],))
        event = sender.step(self.connected,rejected,returns=(CreditReturn(0,"req",0,False,0),
                                                             CreditReturn(0,"orig_data",0,False,0)))
        self.assertFalse(event.control.accepted)
        self.assertIsNone(event.request_payload)
        self.assertIsNone(event.data_payload)
        self.assertIsNone(sender.next_port)
        replacement = StagedBurst(BurstRequest(0,0,False,0,(False,)),0x222,(self.words[3],))
        event = sender.step(self.connected,replacement)
        self.assertTrue(event.control.accepted)
        self.assertEqual(event.request_payload,0x222)
        self.assertEqual(event.data_payload,self.words[3])
        self.assertIsNone(sender.step(self.connected).data_payload)


if __name__ == "__main__":
    unittest.main()
