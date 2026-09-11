"""Exact combinational BLIF output-cone partitioning.

Run test_proof_partitions.py for qualification. No tool jobs are started here.
Next compare every audited partition and establish sequential reset relations.
"""
from collections import Counter


def need(condition, message):
    if not condition:
        raise ValueError(message)


class Network:
    def __init__(self, raw):
        blocks = []
        for line in raw.splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            if line.startswith('.'):
                need(line.split()[0] in ('.model', '.inputs', '.outputs', '.names', '.end'),
                     'unexpanded or sequential BLIF directive')
                blocks.append([line])
            else:
                need(blocks and blocks[-1][0].startswith('.names '), 'orphan truth table')
                blocks[-1].append(line)
        for directive in ('.model', '.inputs', '.outputs', '.end'):
            need(sum(b[0].split()[0] == directive for b in blocks) == 1,
                 'missing or repeated BLIF declaration')
        declarations = {b[0].split()[0]: b[0].split()[1:] for b in blocks
                        if b[0].split()[0] != '.names'}
        need(len(declarations['.model']) == 1, 'invalid module declaration')
        self.model = declarations['.model'][0]
        self.inputs, self.outputs = declarations['.inputs'], declarations['.outputs']
        need(len(set(self.inputs)) == len(self.inputs), 'duplicate input')
        need(len(set(self.outputs)) == len(self.outputs), 'duplicate output')
        self.nodes = {}
        for block in blocks:
            words = block[0].split()
            if words[0] != '.names':
                continue
            need(len(words) >= 2 and words[-1] not in self.nodes, 'duplicate/invalid driver')
            self.nodes[words[-1]] = tuple(block)
        need(not set(self.nodes).intersection(self.inputs), 'input has an internal driver')

    def cone(self, outputs):
        need(outputs and len(outputs) == len(set(outputs)), 'empty or duplicate roots')
        need(set(outputs) <= set(self.outputs), 'unknown output root')
        terminals = set(self.inputs)
        reachable, pending = set(), list(outputs)
        while pending:
            net = pending.pop()
            if net in terminals or net in reachable:
                continue
            need(net in self.nodes, 'undriven live root/cone: ' + net)
            reachable.add(net)
            pending.extend(self.nodes[net][0].split()[1:-1])
        return reachable


def network(value):
    return value if isinstance(value, Network) else Network(value)


def split_outputs(outputs, size):
    need(type(size) is int and size > 0, 'invalid partition size')
    need(outputs and len(outputs) == len(set(outputs)), 'invalid output inventory')
    return [outputs[i:i + size] for i in range(0, len(outputs), size)]


def audit_coverage(outputs, parts):
    need(outputs and len(outputs) == len(set(outputs)), 'invalid original output inventory')
    need(parts and all(parts), 'empty partition')
    need(Counter(x for part in parts for x in part) == Counter(outputs),
         'omitted, duplicate or unknown output root')


def partition(original, outputs):
    source = network(original)
    retained = source.cone(outputs)
    lines = ['.model ' + source.model, '.inputs ' + ' '.join(source.inputs),
             '.outputs ' + ' '.join(outputs)]
    for name, block in source.nodes.items():
        if name in retained:
            lines.extend(block)
    return '\n'.join(lines + ['.end']) + '\n'


def audit_partition(original, candidate, outputs):
    source, actual = network(original), network(candidate)
    need(actual.inputs == source.inputs, 'original input inventory changed')
    need(actual.outputs == list(outputs), 'observed output roots changed')
    needed = source.cone(outputs)
    need(set(actual.nodes) == needed, 'original cone coverage changed')
    need(all(block == source.nodes[name] for name, block in actual.nodes.items()),
         'actual logic equation changed')
    need(actual.cone(outputs) == needed, 'undriven or hidden logic')
    return {'input_bits': len(actual.inputs), 'output_bits': len(actual.outputs),
            'logic_nodes': len(actual.nodes), 'all_equations_preserved': True}
