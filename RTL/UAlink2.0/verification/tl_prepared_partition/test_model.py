"""Run python3 verification/tl_prepared_partition/test_model.py; no output files.
Checks ownership against literal field/tag outcomes. Next run actual RTL vectors.
"""
from pathlib import Path
import importlib.util
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'model/tl'))
FIELDS = [(2 << 60) | (1 << 37) | (j << 47) for j in range(4)]
WORD = sum(x << (64*j) for j, x in enumerate(FIELDS))
TAGS = sum((101+j) << (64*j) for j in range(8))


class Tests(unittest.TestCase):
    def model(self):
        self.assertIsNotNone(importlib.util.find_spec('prepared_partition'), 'registered ownership model missing')
        from prepared_partition import PreparedPartitioner
        return PreparedPartitioner()

    def test_capture_is_separate_from_retirement_and_live_noise_cannot_change_stall(self):
        m = self.model()
        first = m.step(WORD, TAGS, [1]*20, response=True, auth=True, ready=False)
        self.assertTrue(first['captured']); self.assertFalse(first['valid'])
        for j in range(4):
            stalled = m.step(0, 0, [0]*20, valid=True, ready=False, done=False)
            self.assertEqual((stalled['word'], stalled['tags'], stalled['end']), (FIELDS[j] << (64*j), 101+j, 2*(j+1)))
            self.assertTrue(stalled['valid']); self.assertFalse(stalled['captured'])
            sent = m.step(0, 0, [0]*20, valid=False, done=False)
            self.assertTrue(sent['taken']); self.assertEqual(sent['group_done'], j == 3)
        self.assertFalse(m.step(0, 0, [0]*20, valid=False)['valid'])

    def test_final_retirement_and_replacement_has_no_bubble(self):
        m = self.model()
        m.step(FIELDS[0], 101, [8]*20, response=True, auth=True)
        for tag in range(102, 202):
            out = m.step(FIELDS[0], tag, [8]*20, response=True, auth=True)
            self.assertEqual(out['tags'], tag-1)
            self.assertTrue(out['captured'] and out['group_done'])
        self.assertEqual(m.step(0, 0, [0]*20, valid=False)['tags'], 201)

    def test_done_gates_capture_and_reset_cancels_partial_group(self):
        m = self.model()
        self.assertFalse(m.step(WORD, TAGS, [1]*20, done=False)['captured'])
        m.step(WORD, TAGS, [1]*20, response=True, auth=True)
        self.assertEqual(m.step(0, 0, [0]*20, valid=False)['end'], 2)
        out = m.step(WORD, TAGS, [1]*20, reset=True)
        self.assertEqual((out['cursor'], out['word'], out['tags']), (0, 0, 0))
        self.assertFalse(out['captured'] or out['valid'] or out['group_done'])
        self.assertFalse(m.step(0, 0, [0]*20, valid=False)['valid'])

    def test_error_and_shortfall_own_input_until_reset(self):
        for word, caps, expected in [(0, [8]*20, 'error'), (FIELDS[0], [0]*20, 'shortfall')]:
            m = self.model()
            self.assertTrue(m.step(word, 0, caps, response=True)['captured'])
            for _ in range(3):
                out = m.step(WORD, TAGS, [8]*20, response=True)
                self.assertTrue(out[expected])
                self.assertFalse(out['valid'] or out['captured'] or out['source_ready'])
            m.step(0, 0, [0]*20, reset=True)
            self.assertTrue(m.step(WORD, TAGS, [8]*20, response=True)['captured'])

    def test_capacity_snapshot_is_not_aliased(self):
        m = self.model(); caps = [1]*20
        m.step(WORD, TAGS, caps, response=True, auth=True)
        caps[:] = [8]*20
        out = m.step(0, 0, caps, valid=False)
        self.assertEqual((out['fields'], out['end']), (1, 2))


if __name__ == '__main__':
    unittest.main()
