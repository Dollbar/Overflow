"""Service starvation, UART ownership and exact-time acceptance checks."""
import importlib
import itertools
import unittest

GROUPS = ((0, 1, 2, 3, 4), (5, 6), (7, 8, 9, 10))
HISTORIES = tuple(itertools.product(range(3), range(5), range(2), range(4)))
RESET = (2, 4, 1, 3)


def choose(history, pending):
    """Independent explicit next-cursor walk, never calls the solver selector."""
    for offset in range(1, 4):
        group = (history[0] + offset) % 3
        members = GROUPS[group]
        for local in range(1, len(members) + 1):
            source = members[(history[group + 1] + local) % len(members)]
            if pending & (1 << source):
                result = list(history)
                result[0] = group
                result[group + 1] = members.index(source)
                return source, tuple(result)
    raise ValueError('empty test stimulus')


class MessageServiceTests(unittest.TestCase):
    def setUp(self):
        try:
            self.api = importlib.import_module('model.ualink.dl_message_service')
        except ModuleNotFoundError:
            self.fail('DL message service bound implementation is missing')

    def test_all_competing_masks_obey_certificate_and_witness_attains_it(self):
        # Catches an omitted adversarial eligibility choice or underestimated cost.
        maxima = []
        for target in range(11):
            maximum = 0
            rivals = [n for n in range(11) if n != target]
            masks = [1 << target | sum(((m >> i) & 1) << n for i, n in enumerate(rivals))
                     for m in range(1024)]
            for history in HISTORIES:
                bound = self.api.service_bound(history, target)
                maximum = max(maximum, bound.opportunities)
                for pending in masks:
                    winner, after = choose(history, pending)
                    cost = 33 if winner == 7 else 1
                    if winner != target:
                        cost += self.api.service_bound(after, target).opportunities
                    self.assertLessEqual(cost, bound.opportunities)
                current, total = history, 0
                self.assertTrue(bound.steps)
                for index, step in enumerate(bound.steps):
                    self.assertTrue(step.pending & (1 << target))
                    winner, current = choose(current, step.pending)
                    self.assertEqual((step.source, step.after), (winner, current))
                    self.assertEqual(step.words, 33 if winner == 7 else 1)
                    self.assertEqual(winner == target, index == len(bound.steps) - 1)
                    total += step.words
                self.assertEqual(total, bound.opportunities)
            maxima.append(maximum)
        self.assertEqual(maxima, [175, 175, 175, 175, 175, 70, 70, 44, 44, 44, 44])

    def test_every_boundary_history_has_a_real_reset_prefix(self):
        # Catches arbitrary unreachable initialization being substituted for reset.
        for history in HISTORIES:
            current = RESET
            for source in self.api.reset_prefix(history):
                _, current = choose(current, 1 << source)
            self.assertEqual(current, history)

    def test_locked_uart_residual_is_paid_before_new_target(self):
        # Catches dropping residual payload or retaining pre-completion UART cursor.
        maxima = [0] * 11
        for basic, control, remaining, target in itertools.product(range(5), range(2), range(1, 33), range(11)):
            history = (0, basic, control, 3)
            actual = self.api.locked_service_bound(history, target, remaining)
            after = (2, basic, control, 0)
            expected = remaining if target == 7 else remaining + self.api.service_bound(after, target).opportunities
            self.assertEqual(actual, expected)
            maxima[target] = max(maxima[target], actual)
        self.assertEqual(maxima, [173, 173, 173, 173, 173, 69, 69, 32, 35, 38, 41])

    def test_saturated_all_sources_is_not_the_worst_basic_wait(self):
        # Catches treating all sources continuously ready as the worst adversary.
        history, count = (0, 2, 0, 3), 0
        while True:
            source, history = choose(history, 2047)
            count += 33 if source == 7 else 1
            if source == 2:
                break
        self.assertEqual(count, 79)
        self.assertEqual(self.api.service_bound((0, 2, 0, 3), 2).opportunities, 175)

    def test_time_budget_counts_phase_all_gaps_and_both_pipelines(self):
        # Hand arithmetic: 100 + 7 + 3*11 + 20 + 40 = 200 ps.
        result = self.api.completion_budget(4, first_ps=7, gap_ps=11,
                                           ingress_ps=100, egress_ps=40, blackout_ps=20,
                                           deadline_ps=200)
        self.assertEqual((result.completion_ps, result.margin_ps, result.meets_deadline), (200, 0, True))
        result = self.api.completion_budget(4, first_ps=7, gap_ps=11,
                                           ingress_ps=100, egress_ps=41, blackout_ps=20,
                                           deadline_ps=200)
        self.assertEqual((result.completion_ps, result.margin_ps, result.meets_deadline), (201, -1, False))

    def test_microsecond_is_not_rounded_up_to_157_slow_cycles(self):
        for opportunities, expected, passed in ((156, 998400, True), (157, 1004800, False), (175, 1120000, False)):
            result = self.api.completion_budget(opportunities, first_ps=6400, gap_ps=6400)
            self.assertEqual((result.completion_ps, result.meets_deadline), (expected, passed))
        result = self.api.completion_budget(70, first_ps=12800, gap_ps=12800)
        self.assertEqual((result.completion_ps, result.margin_ps), (896000, 104000))

    def test_unknown_service_or_unbounded_replay_never_certifies_deadline(self):
        for first, gap, blackout in ((None, 640, 0), (640, None, 0), (640, 640, None)):
            result = self.api.completion_budget(1, first_ps=first, gap_ps=gap, blackout_ps=blackout)
            self.assertEqual((result.completion_ps, result.margin_ps, result.meets_deadline), (None, None, None))

    def test_invalid_limits_are_rejected_even_when_service_unknown(self):
        for kwargs in ({'opportunities':0}, {'opportunities':True}, {'gap_ps':0}, {'ingress_ps':-1},
                       {'egress_ps':1.5}, {'blackout_ps':-1}, {'deadline_ps':False}, {'first_ps':-1}):
            values = dict(opportunities=1, first_ps=None, gap_ps=None)
            values.update(kwargs)
            with self.assertRaises(ValueError):
                self.api.completion_budget(**values)
        for history, target in (((3,0,0,0),0), ((0,5,0,0),0), (RESET,11), (RESET,True), ([2,4,1,3],0)):
            with self.assertRaises(ValueError):
                self.api.service_bound(history,target)
        for remaining in (0,33,True):
            with self.assertRaises(ValueError):
                self.api.locked_service_bound(RESET,2,remaining)

if __name__ == '__main__':
    unittest.main()
