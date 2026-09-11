"""Run python3 verification/tl_tx_prepared/test_proof_partitions.py.
Outputs unittest results. Next run source-bound actual mapped CEC partitions.
"""
import itertools
import unittest

from proof_partitions import split_outputs, partition, audit_partition, audit_coverage


CIRCUIT = '''.model literal
.inputs a b
.outputs public next
.names a b public
10 1
01 1
.names a b product
11 1
.names product next
0 1
.names missing dead
1 1
.end
'''


def simulate(raw, a, b):
    values = {'a': a, 'b': b}
    rows = raw.splitlines()
    index = 0
    while index < len(rows):
        row = rows[index].split()
        index += 1
        if not row or row[0] != '.names':
            continue
        inputs, output = row[1:-1], row[-1]
        values[output] = 0
        while index < len(rows) and not rows[index].startswith('.'):
            pattern, value = rows[index].split()
            if all(bit == '-' or int(bit) == values[name]
                   for bit, name in zip(pattern, inputs)):
                values[output] = int(value)
            index += 1
    return values


class ProofPartitions(unittest.TestCase):
    def test_each_root_keeps_its_actual_function(self):
        for root, expected in [('public', [0, 1, 1, 0]),
                               ('next', [1, 1, 1, 0])]:
            actual = partition(CIRCUIT, [root])
            self.assertEqual([simulate(actual, a, b)[root]
                              for a, b in itertools.product((0, 1), repeat=2)], expected)
            audit_partition(CIRCUIT, actual, [root])

    def test_changed_truth_table_rejected(self):
        actual = partition(CIRCUIT, ['next']).replace('11 1', '10 1')
        with self.assertRaises(ValueError):
            audit_partition(CIRCUIT, actual, ['next'])

    def test_changed_input_rejected(self):
        actual = partition(CIRCUIT, ['next']).replace('.inputs a b', '.inputs a b invented')
        with self.assertRaises(ValueError):
            audit_partition(CIRCUIT, actual, ['next'])

    def test_next_state_is_not_lost_in_partition_plan(self):
        parts = split_outputs(['public', 'next'], 1)
        self.assertEqual(parts, [['public'], ['next']])
        audit_coverage(['public', 'next'], parts)
        for changed in ([['public']], [['public'], ['public'], ['next']]):
            with self.assertRaises(ValueError):
                audit_coverage(['public', 'next'], changed)

    def test_missing_or_duplicate_root_rejected(self):
        for roots in ([], ['missing'], ['public', 'public']):
            with self.assertRaises(ValueError):
                partition(CIRCUIT, roots)

    def test_undriven_live_root_rejected(self):
        with self.assertRaises(ValueError):
            partition(CIRCUIT.replace('.outputs public next', '.outputs public dead'), ['dead'])

    def test_changed_observed_root_rejected(self):
        with self.assertRaises(ValueError):
            audit_partition(CIRCUIT, partition(CIRCUIT, ['public']), ['next'])

    def test_invalid_chunk_size_rejected(self):
        for size in (0, -1, True):
            with self.assertRaises(ValueError):
                split_outputs(['public', 'next'], size)


if __name__ == '__main__':
    unittest.main()
