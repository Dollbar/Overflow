"""Independent absolute-cycle TDM oracle; does not import RTL helpers or UpliTdm."""
import random

class Timeline:
    def __init__(self, ports):
        if ports not in (1, 2, 4):
            raise ValueError('ports must be 1/2/4')
        self.ports = ports
        self.cycle = 0
        self.epochs = [None] * 3
        self.sticky = 0

    def state(self):
        known = sum((epoch is not None) << g for g, epoch in enumerate(self.epochs))
        phases = sum((((self.cycle - epoch[0] + epoch[1]) % self.ports) if epoch else 0) << (2*g)
                     for g, epoch in enumerate(self.epochs))
        return known, phases, self.sticky

    def step(self, rstn, valid, ports):
        before = self.state()
        errors = 0
        learned = list(self.epochs)
        if rstn:
            for channel in range(4):
                if not (valid >> channel) & 1:
                    continue
                group = 0 if channel < 2 else channel - 1
                port = ports[channel]
                if port >= self.ports:
                    errors |= 1 << channel
                    continue
                epoch = learned[group]
                if epoch is None:
                    if channel == 1:
                        errors |= 1 << channel
                    else:
                        learned[group] = (self.cycle, port)
                elif port != (self.cycle - epoch[0] + epoch[1]) % self.ports:
                    errors |= 1 << channel
            self.epochs = learned
            self.sticky |= errors
        else:
            self.epochs = [None] * 3
            self.sticky = 0
        self.cycle += 1
        return (errors, *before), self.state()


def generate(path, ports):
    oracle = Timeline(ports)
    rows = []
    coverage = {'errors_by_channel': [0]*4, 'valid_by_channel': [0]*4, 'resets': 0, 'idle': 0}
    def put(reset, valid, ps):
        pre, post = oracle.step(reset, valid, ps)
        rows.append((reset, valid, sum(p << (2*i) for i,p in enumerate(ps)), *pre, *post))
        coverage['resets'] += not reset
        coverage['idle'] += not valid
        for ch in range(4):
            coverage['errors_by_channel'][ch] += (pre[0] >> ch) & 1
            coverage['valid_by_channel'][ch] += (valid >> ch) & 1
    put(0, 15, [3]*4)
    for start in range(ports):
        put(0, 0, [3]*4)
        put(1, 2, [0, start, 0, 0])  # orphan OrigData cannot learn.
        put(1, 0, [3]*4)
        put(1, 3, [start, start, 0, 0])
        for _ in range(7):
            put(1, 0, [3]*4)
        known, phase, _ = oracle.state()
        put(1, 3, [phase & 3, phase & 3, 0, 0])
        put(1, 4, [0, 0, (start+1) % ports, 0])
        put(1, 0, [3]*4)
        put(1, 8, [0, 0, 0, (start+2) % ports])
        for _ in range(20):
            _, phase, _ = oracle.state()
            put(1, 15, [phase & 3, phase & 3, (phase >> 2) & 3, phase >> 4])
    # Every native valid mask and every representable PortID tuple, even idle fields.
    for mask in range(16):
        for packed in range(256):
            if packed % 32 == 0:
                put(0, 0, [0]*4)
            put(1, mask, [(packed >> (2*i)) & 3 for i in range(4)])
    rng = random.Random(0x54444d + ports)
    for cycle in range(4000):
        _, phase, _ = oracle.state()
        ps = [phase & 3, phase & 3, (phase >> 2) & 3, phase >> 4]
        if cycle % 3 == 0:
            ps = [rng.randrange(4) for _ in range(4)]
        put(cycle % 277 != 0, rng.randrange(16), ps)
    put(0, 15, [3]*4)
    path.write_text(''.join(' '.join(f'{n:x}' for n in row)+'\n' for row in rows))
    return {'rows':len(rows), 'coverage':coverage, 'oracle':'absolute cycle epochs; valid bit0 req/1 data/2 rd/3 wr'}
