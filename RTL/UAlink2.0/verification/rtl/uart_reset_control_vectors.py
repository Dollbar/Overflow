"""Generate exact edge vectors from the event-based UART reset cycle reference.

Run: python3 verification/rtl/uart_reset_control_vectors.py --output vectors.mem --summary vectors.json
Outputs: repeat/input/pre/post hexadecimal rows and exact event counts.
Next: run the actual RTL clock for EVERY repeated edge, including full 10ms waits.
"""
import argparse
from dataclasses import fields
import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.uart_reset_control import UARTResetControl, UARTResetSignals

OUTPUT_WIDTHS = (1, 1, 1, 1, 32, 2, 1, 6, 5, 1, 1, 1, 1, 1, 1)
COUNTERS = ('rows', 'edges', 'noops', 'requests', 'replies', 'starts',
            'successes', 'retries', 'errors')


def pack_output(out):
    result = 0
    for field, width in zip(fields(UARTResetSignals), OUTPUT_WIDTHS, strict=True):
        value = int(getattr(out, field.name))
        assert 0 <= value < 1 << width, (field.name, value)
        result = result << width | value
    assert sum(OUTPUT_WIDTHS) == 56
    return result


def pack_input(inputs):
    result = int(not inputs.get('reset', False))
    for name, width in (('local_request', 1), ('local_all', 1), ('rx_request', 1),
                        ('request_all', 1), ('rx_response', 1), ('response_status', 3),
                        ('tx_take', 1)):
        result = result << width | int(inputs.get(name, 0))
    return result


class Campaign:
    def __init__(self, period, depth, seed):
        self.model = UARTResetControl(period, depth)
        self.rng = random.Random(seed)
        self.lines = []
        self.counts = dict.fromkeys(COUNTERS, 0)
        self.profiles = []

    def record(self, count, inputs, before, after):
        assert 0 < count < 1 << 34
        self.lines.append(f'{count:09x} {pack_input(inputs):03x} '
                          f'{pack_output(before):014x} {pack_output(after):014x}\n')
        self.counts['rows'] += 1
        self.counts['edges'] += count
        for key, active in (('starts', before.local_start), ('successes', before.local_done),
                            ('retries', before.retry), ('errors', before.error)):
            self.counts[key] += int(active) * count
        if before.tx_pending and inputs.get('tx_take', False):
            self.counts[{1: 'noops', 2: 'requests', 3: 'replies'}[before.tx_kind]] += count

    def edge(self, **inputs):
        before = self.model.tick(**inputs)
        self.record(1, inputs, before, self.model.observe(**inputs))
        return before

    def idle(self, count):
        if count:
            before = self.model.idle(count)
            self.record(count, {}, before, self.model.observe())

    def reset(self):
        self.edge(reset=True, local_request=True, rx_request=True,
                  rx_response=True, response_status=7, tx_take=True)
        self.edge()

    def runout(self, *, all_streams=False, fresh=True, stalls=True):
        if fresh:
            assert self.edge(local_request=True, local_all=all_streams).local_start
        for index in range(40):
            if stalls:
                self.idle(self.rng.randrange(3))
            out = self.edge(tx_take=True, local_request=(index % 7 == 0),
                            local_all=not all_streams, rx_response=True,
                            response_status=index % 8)
            assert (out.tx_kind, out.tx_word, out.noops_left) == (1, 0, 40-index)
        self.idle(13)  # Request cannot start its timeout while it is still stalled.
        out = self.edge(tx_take=True, rx_response=True, response_status=0)
        assert (out.tx_kind, out.tx_word) == (2, 0x184 | int(all_streams) << 12)
        assert not out.local_done and self.model.observe().waiting

    def directed(self):
        depth = self.model.response_depth
        cycles = (10_000_000_000 + self.model.period_ps - 1) // self.model.period_ps
        self.profiles.append('real_timeout_then_retry_and_deadline_success')
        self.reset()
        self.runout(all_streams=True)
        self.edge(rx_request=True, request_all=True)
        assert self.edge(tx_take=True).reply_done
        assert self.model.observe().waiting  # Replying to peer cannot finish our wait.
        self.idle(cycles-3)
        out = self.edge(rx_response=True, response_status=7, rx_request=True, request_all=False)
        assert out.retry and not out.local_done
        self.runout(all_streams=True, fresh=False)
        out = self.edge(rx_response=True, tx_take=True)
        assert out.local_done and out.reply_done
        assert not self.model.observe().stream_reset
        self.runout(all_streams=False)
        self.idle(cycles-1)
        out = self.edge(rx_response=True, rx_request=True, request_all=True)
        assert out.local_done and not out.retry
        assert self.model.observe().stream_reset
        assert self.edge(tx_take=True).reply_done

        self.profiles.append('ordered_full_queue_replace_and_drain')
        for index in range(depth):
            assert not self.edge(rx_request=True, request_all=bool(index % 2)).error
        for index in range(depth*3):
            out = self.edge(rx_request=True, request_all=bool((index//2) % 2), tx_take=True)
            assert out.reply_done and not out.error
            assert self.model.observe().response_count == depth
        for _ in range(depth):
            assert self.edge(tx_take=True).reply_done

        self.profiles.append('full_queue_overflow_and_sticky_fault_recovery')
        for _ in range(depth):
            self.edge(rx_request=True)
        assert self.edge(rx_request=True).error
        self.idle(7)
        self.edge(local_request=True, rx_response=True, rx_request=True, tx_take=True)
        assert self.model.observe().fault
        self.reset()
        self.profiles.append('illegal_take_and_local_start_suppressed_offer')
        assert self.edge(tx_take=True).error
        self.reset()
        self.edge(rx_request=True)
        assert self.edge(local_request=True, tx_take=True).error
        self.reset()
        self.profiles.append('overflow_with_real_noop_commit')
        for _ in range(depth):
            self.edge(rx_request=True)
        self.edge(local_request=True)
        out = self.edge(rx_request=True, tx_take=True)
        assert out.error and out.tx_kind == 1 and out.tx_pending
        self.reset()

    def random(self, cycles):
        self.profiles.append('seeded_simultaneous_inputs_stalls_faults_and_recovery')
        for _ in range(cycles):
            if self.model.observe().fault:
                self.edge(reset=self.rng.randrange(4) == 0,
                          local_request=bool(self.rng.getrandbits(1)),
                          rx_request=bool(self.rng.getrandbits(1)),
                          tx_take=bool(self.rng.getrandbits(1)))
                continue
            inputs = dict(reset=self.rng.randrange(509) == 0,
                          local_request=self.rng.randrange(23) == 0,
                          local_all=bool(self.rng.getrandbits(1)),
                          rx_request=self.rng.randrange(31) == 0,
                          request_all=bool(self.rng.getrandbits(1)),
                          rx_response=self.rng.randrange(7) == 0,
                          response_status=self.rng.randrange(8))
            offer = self.model.observe(**inputs)
            inputs['tx_take'] = (offer.tx_pending and self.rng.randrange(4) != 0) or self.rng.randrange(997) == 0
            self.edge(**inputs)
        self.reset()
        assert self.model.observe() == UARTResetSignals(local_ready=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--summary', type=Path, required=True)
    p.add_argument('--period-ps', type=int, default=640)
    p.add_argument('--depth', type=int, default=4)
    p.add_argument('--seed', type=int, default=17)
    p.add_argument('--cycles', type=int, default=4000)
    a = p.parse_args()
    if a.cycles < 1:
        p.error('random cycles must be positive')
    campaign = Campaign(a.period_ps, a.depth, a.seed)
    campaign.directed()
    campaign.random(a.cycles)
    a.output.write_text(''.join(campaign.lines))
    summary = dict(campaign.counts, period_ps=a.period_ps, depth=a.depth, seed=a.seed,
                   random_cycles=a.cycles, profiles=campaign.profiles,
                   output_bits=56, input_bits=10, compressed_storage_only=True,
                   wait_cycles=(10_000_000_000+a.period_ps-1)//a.period_ps)
    a.summary.write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
