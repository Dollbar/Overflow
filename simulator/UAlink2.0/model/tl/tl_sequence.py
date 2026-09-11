"""Common2.0 half-flit class sequencing; field-derived tenure is an explicit input.
D = data/atomic operand half-flit; B = byte-enable half-flit.
This classifier does not validate payloads or paired 64-byte poisoning.
"""
class SequenceError(ValueError):
    pass

class Sequencer:
    def __init__(self, *, auth=False):
        if type(auth) is not bool:raise TypeError('auth must be bool')
        self.auth=auth
        self.pending=()

    def step(self, *, msg=(None,None), fields=0, tenure=(), transfer=True, reset=False):
        if type(transfer) is not bool or type(reset) is not bool:raise TypeError('controls must be bool')
        if reset:
            self.pending=()
            return 'RESET','RESET'
        if type(fields) is not int or not 0<=fields<=8:raise SequenceError('invalid field count')
        if len(msg)!=2 or any(x is not None and (type(x) is not int or x not in (0,1,32)) for x in msg):raise SequenceError('reserved message type')
        tokens=tuple(tenure)
        if any(x not in ('D','B') for x in tokens):raise SequenceError('invalid tenure token')
        queue=list(self.pending)
        def consume(message, expected):
            if expected=='AUTH':
                if message is not None:raise SequenceError('message cannot replace AuthTags')
                return 'AUTH'
            if message==32:
                if expected!='DATA':raise SequenceError('poison requires data or operands')
                queue.pop(0)
                return 'POISON'
            if message is not None:return 'MESSAGE'
            if expected in ('DATA','BYTE_ENABLE'):queue.pop(0)
            return expected
        if len(queue)<=1:
            trailing=bool(queue)
            if msg[0]==32:raise SequenceError('lower control slot cannot be poisoned')
            if msg[0] is None:
                if self.auth and (fields>4 or (trailing and fields)):
                    raise SequenceError('authentication count or swapped-tail restriction')
                if tokens and fields==0:raise SequenceError('tenure requires a data-bearing field')
                lower='CONTROL'
                queue.extend(tokens)
                if trailing:upper_expected='DATA' if queue[0]=='D' else 'BYTE_ENABLE'
                elif self.auth and fields:upper_expected='AUTH'
                elif queue:upper_expected='DATA' if queue[0]=='D' else 'BYTE_ENABLE'
                else:upper_expected='NOP'
            else:
                lower='MESSAGE'
                upper_expected=('DATA' if queue[0]=='D' else 'BYTE_ENABLE') if trailing else 'NOP'
            upper=consume(msg[1],upper_expected)
        else:
            lower=consume(msg[0],'DATA' if queue[0]=='D' else 'BYTE_ENABLE')
            upper=consume(msg[1],'DATA' if queue[0]=='D' else 'BYTE_ENABLE')
        if transfer:self.pending=tuple(queue)
        return lower,upper
