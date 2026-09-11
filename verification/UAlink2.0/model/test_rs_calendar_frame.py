"""Check real calendar/frame ownership; no mocked scheduler or frame engine.
Run: python3 [-O] -m unittest verification.model.test_rs_calendar_frame -v
Output: directed cycle assertions. Next: mutations and actual RTL integration.
"""
import unittest
from model.ualink.rs_calendar_frame import CalendarFrame, CalendarConfig
from model.ualink import rs_block_codec as codec

PROFILES = ((100, 1, 4096), (100, 2, 4096), (100, 4, 8192),
            (200, 1, 4096), (200, 2, 8192), (200, 4, 16384))


class CalendarFrameTests(unittest.TestCase):
    def test_initial_control_only_commits_on_last_group(self):
        # Missing command admission or counting admission as transmission breaks this.
        dut = CalendarFrame(200, 1, 8)
        dut.tick(reset=True)
        first = dut.tick()
        self.assertTrue(first.frame.command_accepted)
        self.assertEqual(first.phase, 0)
        for beat in range(10):
            out = dut.tick(flit_valid=True, data=bytes(64))
            self.assertEqual(out.frame.index, beat * 8)
            self.assertEqual(out.phase, 0)
            self.assertEqual(out.next_phase, int(beat == 9))
            self.assertEqual(out.next_kind, 'dl_flit' if beat == 9 else 'alignment_marker')
            self.assertFalse(out.frame.data_consumed)
            self.assertFalse(out.dl_completed)
            self.assertEqual(out.codeword_completed, beat == 9)
            self.assertEqual(out.flit_reserved, beat == 9)
        self.assertEqual(dut.outputs(data=bytes(64)).phase, 1)

    def _load(self, n=8, phase=1, rapid=False, serial=200, lanes=1,
              resiliency=False, pl_id=0):
        dut = CalendarFrame(serial, lanes, n)
        dut.tick(phase_load=CalendarConfig(phase, rapid, resiliency, pl_id))
        return dut

    def test_reservation_does_not_consume_first_data_group(self):
        # Conflating descriptor reservation and payload consumption loses bytes.
        for n in (1, 2, 4, 8):
            dut = self._load(n=n)
            first = dut.tick(flit_valid=True, data=bytes(8*n))
            self.assertTrue(first.flit_ready)
            self.assertTrue(first.flit_reserved)
            self.assertFalse(first.frame.data_consumed)
            self.assertFalse(first.codeword_completed)
            received = bytearray()
            for beat in range(80//n):
                data = bytes((beat*8*n+j) % 256 for j in range(8*n))
                out = dut.tick(data=data)
                self.assertTrue(out.frame.data_consumed)
                for block, start in zip(out.frame.blocks, range(0, len(data), 8)):
                    self.assertEqual(block, codec.encode_block('data', data[start:start+8]))
                received.extend(data)
                self.assertEqual(out.dl_completed, beat == 80//n-1)
                self.assertEqual(out.phase, 1)
            self.assertEqual(len(received), 640)
            self.assertEqual(dut.outputs().phase, 2)
            self.assertTrue(dut.outputs().starved)

    def test_missing_descriptor_is_explicit_starvation(self):
        # Fabricating a DL NOP or advancing an empty slot breaks this.
        dut = self._load()
        for _ in range(20):
            out = dut.tick(data=bytes(64))
            self.assertTrue(out.flit_ready)
            self.assertTrue(out.starved)
            self.assertFalse(out.flit_reserved)
            self.assertFalse(out.frame.output_valid)
            self.assertEqual(out.phase, 1)

    def test_payload_starvation_waits_without_second_reservation(self):
        # Using the next descriptor to qualify current payload corrupts ownership.
        dut = self._load()
        dut.tick(flit_valid=True)
        for _ in range(5):
            out = dut.tick(flit_valid=True)
            self.assertTrue(out.starved)
            self.assertFalse(out.flit_ready)
            self.assertFalse(out.frame.output_valid)
            self.assertEqual(out.frame.index, 0)
        self.assertFalse(dut.outputs(ready=False).starved)
        self.assertTrue(dut.tick(data=bytes(64)).frame.data_consumed)

    def test_last_missing_data_cannot_advance_or_reserve(self):
        # Last-index alone is insufficient to complete a frame.
        dut = self._load(phase=1023)
        dut.tick(flit_valid=True)
        for _ in range(9):
            dut.tick(data=bytes(64))
        for _ in range(4):
            out = dut.tick(flit_valid=True)
            self.assertEqual(out.frame.index, 72)
            self.assertEqual(out.phase, 1023)
            self.assertEqual(out.next_kind, 'dl_flit')
            self.assertFalse(out.codeword_completed)
            self.assertFalse(out.flit_reserved)
        done = dut.tick(flit_valid=True, data=bytes(64))
        self.assertTrue(done.dl_completed)
        self.assertTrue(done.frame.command_accepted)
        self.assertFalse(done.flit_reserved)
        self.assertEqual(done.next_kind, 'rate_idle')

    def test_last_backpressure_preserves_complete_old_output(self):
        # Lookahead must use actual last transfer, and never overwrite old output.
        dut = self._load(phase=1023)
        dut.tick(flit_valid=True)
        for _ in range(9):
            dut.tick(data=bytes(64))
        data = bytes(range(64))
        held = dut.outputs(data=data, ready=False)
        for _ in range(5):
            self.assertEqual(dut.tick(flit_valid=True, data=data, ready=False), held)
        done = dut.tick(flit_valid=True, data=data)
        self.assertEqual(done.frame.blocks, held.frame.blocks)
        self.assertEqual(done.frame.metadata.kind, 0)
        nxt = dut.outputs()
        self.assertEqual(nxt.phase, 1024)
        self.assertEqual(nxt.frame.index, 0)
        self.assertEqual(nxt.frame.metadata.kind, 1)
        self.assertEqual(nxt.frame.metadata.marker, 0)

    def test_literal_calendar_boundaries_all_24_profiles(self):
        # Old-phase preselection, wrong profile periods and extra RAM Idles fail.
        for serial, lanes, period in PROFILES:
            for n in (1, 2, 4, 8):
                for rapid, start, expected in (
                    (False, 1023, ('dl_flit', 'rate_idle', 'dl_flit')),
                    (False, period-1, ('dl_flit', 'alignment_marker', 'dl_flit')),
                    (True, period//128-1, ('dl_flit', 'rapid_alignment_marker', 'dl_flit')),
                    (True, 1023, ('dl_flit', 'rapid_alignment_marker', 'dl_flit')),
                    (False, 16383, ('dl_flit', 'alignment_marker', 'dl_flit'))):
                    with self.subTest(serial=serial, lanes=lanes, n=n, rapid=rapid, start=start):
                        dut = self._load(n, start, rapid, serial, lanes, True, 1)
                        self.assertEqual(dut.tick(flit_valid=True).next_kind, expected[0])
                        for frame_no, kind in enumerate(expected):
                            gathered = []
                            for beat in range(80//n):
                                out = dut.tick(flit_valid=True, data=bytes(8*n))
                                self.assertTrue(out.frame.output_taken)
                                self.assertEqual(out.phase, (start+frame_no) % 16384)
                                self.assertEqual(out.frame.index, beat*n)
                                self.assertEqual(out.codeword_completed, beat == 80//n-1)
                                gathered.extend(out.frame.blocks)
                                if beat == 80//n-1 and frame_no < 2:
                                    self.assertEqual(out.next_kind, expected[frame_no+1])
                                    self.assertEqual(out.flit_reserved, expected[frame_no+1] == 'dl_flit')
                            if kind != 'dl_flit':
                                marker = {'alignment_marker':'am','rapid_alignment_marker':'ram','rate_idle':None}[kind]
                                want = codec.encode_control_flit('idle', marker=marker,
                                    am_next_count=255 if marker == 'ram' else None,
                                    link_resiliency=True, pl_id=1)
                                self.assertEqual(tuple(gathered), want)
                            else:
                                self.assertEqual(tuple(gathered), (codec.encode_block('data', bytes(8)),)*80)

    def test_all_control_configurations_remain_captured(self):
        # Wrong RAM count or dropping resiliency/PL ID corrupts first/tail fields.
        for rapid in (False, True):
            for resiliency in (False, True):
                for pl_id in (0, 1):
                    dut = self._load(phase=0, rapid=rapid, resiliency=resiliency, pl_id=pl_id)
                    dut.tick()
                    blocks = []
                    for _ in range(10):
                        out = dut.tick()
                        blocks.extend(out.frame.blocks)
                        self.assertFalse(out.frame.data_consumed)
                    expected = codec.encode_control_flit('idle', marker='ram' if rapid else 'am',
                        am_next_count=255 if rapid else None, link_resiliency=resiliency, pl_id=pl_id)
                    self.assertEqual(tuple(blocks), expected)

    def test_load_cancels_pending_last_without_completion(self):
        # Loading phase while still emitting the old last group is a double commit.
        for beat_count in (0, 1, 9):
            dut = self._load()
            dut.tick(flit_valid=True)
            for _ in range(beat_count):
                dut.tick(data=bytes(64))
            out = dut.tick(flit_valid=True, data=bytes(64),
                           phase_load=CalendarConfig(32, True, True, 1))
            self.assertEqual(out.phase, 1)
            self.assertIsNone(out.next_kind)
            self.assertFalse(out.codeword_completed)
            self.assertFalse(out.frame.output_valid)
            self.assertFalse(out.frame.command_accepted)
            self.assertFalse(out.frame.data_consumed)
            self.assertFalse(out.flit_ready)
            self.assertFalse(out.starved)
            self.assertEqual(dut.outputs().phase, 32)
            self.assertEqual(dut.tick().next_kind, 'rapid_alignment_marker')
            self.assertEqual(dut.outputs().frame.metadata.count, 255)

    def test_reset_has_priority_over_phase_and_mode_load(self):
        # Reset must discard both an active frame and concurrent recovery config.
        dut = self._load(phase=31, rapid=True, resiliency=True, pl_id=1)
        dut.tick(flit_valid=True)
        out = dut.tick(reset=True, phase_load=CalendarConfig(1024, True, True, 1),
                       flit_valid=True, data=bytes(64))
        self.assertFalse(out.frame.output_taken)
        self.assertFalse(out.flit_reserved)
        self.assertEqual(dut.tick().next_kind, 'alignment_marker')
        current = dut.outputs()
        self.assertEqual(current.phase, 0)
        self.assertFalse(current.frame.metadata.resiliency)
        self.assertEqual(current.frame.metadata.pl_id, 0)

    def test_output_evaluation_does_not_advance_or_capture_config(self):
        # Repeated combinational reads must not advance phase/index or apply a load.
        dut = self._load()
        dut.tick(flit_valid=True)
        before = dut.outputs(data=bytes(64))
        for _ in range(8):
            dut.outputs(phase_load=CalendarConfig(1024, True))
            self.assertEqual(dut.outputs(data=bytes(64)), before)

    def test_configuration_is_immutable_and_strictly_typed(self):
        # Ambiguous bool/int coercions would differ from the intended bus API.
        from dataclasses import FrozenInstanceError
        config = CalendarConfig(0)
        with self.assertRaises(FrozenInstanceError):
            config.rapid = True
        for kwargs in ({'phase':-1}, {'phase':16384}, {'phase':True}, {'phase':1.0},
                       {'phase':0,'rapid':1}, {'phase':0,'resiliency':0},
                       {'phase':0,'pl_id':2}, {'phase':0,'pl_id':True}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                CalendarConfig(**kwargs)

    def test_invalid_profiles_and_inputs_are_rejected(self):
        # Unsupported parallelism or silent truthiness is not a valid hardware profile.
        for args in ((50,1,8),(200,3,8),(100,1,3),(True,1,8),(200,True,8),(200,1,True)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                CalendarFrame(*args)
        dut = CalendarFrame(200,1,8)
        for kwargs in ({'flit_valid':1},{'ready':1},{'reset':0},{'phase_load':3},
                       {'data':bytes(63)},{'data':bytearray(64)}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                dut.tick(**kwargs)

    def test_normal_and_rapid_complete_calendars_have_no_interframe_bubble(self):
        # A boundary bubble or per-beat phase count is observable for every codeword.
        for serial, lanes, period in PROFILES:
            for rapid in (False, True):
                dut = self._load(phase=0, rapid=rapid, serial=serial, lanes=lanes)
                dut.tick(flit_valid=True)
                completed = reserved = 0
                for ordinal in range(period):
                    marker_period = period//128 if rapid else period
                    marker = ordinal % marker_period == 0
                    idle = not rapid and ordinal % 1024 == 0 and not marker
                    for beat in range(10):
                        out = dut.tick(flit_valid=True, data=bytes(64))
                        self.assertTrue(out.frame.output_taken)
                        self.assertEqual(out.frame.index, beat*8)
                        self.assertEqual(out.phase, ordinal)
                        self.assertEqual(out.frame.metadata.kind, 1 if marker or idle else 0)
                        self.assertEqual(out.frame.metadata.marker, (2 if rapid else 1) if marker else 0)
                        completed += out.codeword_completed
                        reserved += out.flit_reserved
                self.assertEqual(completed, period)
                self.assertEqual(reserved, period - (128 if rapid else period//1024))


if __name__ == '__main__':
    unittest.main()
