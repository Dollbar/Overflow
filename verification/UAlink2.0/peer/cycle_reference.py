"""Independent public-cycle projection of immutable protocol scheduling models."""
from model.ualink.dl_replay_scheduler import DLReplayScheduler

class CycleReference:
    def __init__(self, depth, width, ports, storage_ports):
        self.depth=depth;self.width=width;self.ports=ports;self.sp=storage_ports
        self.scheduler=DLReplayScheduler(capacity=depth)
        self.head=self.write=self.group=0;self.memory=[None]*depth;self.slot=None
        self.scalar=[(n,w) for n,w in ports['outputs'] if w!='W']
        self.postnames=ports['state_names']+['o_resident_count']+ports['pipe_names']
    def states(self):
        s=self.scheduler;t=s.tx;q=t.state;rx=s.rx.state;hs=s.state
        values=[q.last_sequence,q.last_ack,q.ignore_count,len(t.buffer),self.head,self.write,t.scheduled[0].sequence if t.scheduled else 0,len(t.scheduled),self.memory.index(t.scheduled[0]) if t.scheduled else 0,int(q.first_replay)]
        return dict(zip(self.sp['state_names'],values))|dict(o_resident_count=t.resident_count,o_rx_last_sequence=rx.last_sequence,o_rx_bad_crc_count=rx.bad_crc_count,o_rx_unexpected_count=rx.unexpected_count,o_rx_ambiguous=int(rx.ambiguous),o_rx_replay=int(rx.replay),o_tx_explicit_count=hs.explicit_count,o_tx_request_count=hs.replay_requests,o_tx_request_sequence=hs.request_sequence,o_tx_group_used=int(hs.last_request_group==self.group))
    def pipe(self,active):
        p=self.slot
        if not active or p is None:return dict.fromkeys(self.ports['pipe_names'],0),0
        values=[1,int(p.payload is not None),int(p.replayed),int(p.first_replay),p.sequence,0,p.sequence if p.replayed else 0]
        return dict(zip(self.sp['pipe_names'],values))|{'o_out_header':p.header},int.from_bytes(p.payload,'little') if p.payload is not None else 0
    def cycle(self,packed,data,rxdata):
        inputs={};shift=0
        for n,w in self.ports['inputs'][1:]:
            if w=='W':continue
            inputs[n]=(packed>>shift)&((1<<w)-1);shift+=w
        i=inputs;active=bool(i['i_rstn'] and not i['i_link_reset']);s=self.scheduler;pre=dict.fromkeys((n for n,w in self.scalar),0);pre.update(self.states());out,predata=self.pipe(active);pre.update(out);oldrx=s.rx.state.last_sequence;event=None
        if not active:
            s.reset();self.head=self.write=self.group=0;self.memory=[None]*self.depth;self.slot=None
        else:
            s.rx.configure_replay_limit(i['i_rx_replay_limit'])
            if i['i_rx_event_valid']:
                word=i['i_rx_header'];received=s.discard_ingress() if i['i_rx_event_discard'] else s.receive(word,payload=rxdata.to_bytes(self.width//8,'little') if word&(1<<20) else None,crc_ok=bool(i['i_rx_crc_ok']));event=received.receiver;e=event
                pre.update(o_rx_ingress_event=1,o_rx_accept=int(e.accepted),o_rx_payload_accept=int(e.deliver_payload),o_rx_sequence_valid=int(e.sequence is not None),o_rx_sequence=e.sequence or 0,o_rx_replay_request=int(bool(e.request_replays)))
                if e.command:
                    pre.update(o_rx_command_valid=1,o_rx_command_request=int(e.command.op==3),o_rx_command_target=e.command.ack_request)
                    c=received.command;pre.update(o_ack_accept=int(c.reason=='ack'),o_ack_count=len(c.acknowledged),o_request_accept=int(c.replay_started),o_command_reject=int(c.reason!='ack' and not c.replay_started));self.head=(self.head+len(c.acknowledged))%self.depth
                for n,r in [('o_rx_crc_error','invalid_flit'),('o_rx_zero_sequence','zero_sequence'),('o_rx_zero_command','zero_ack_request'),('o_rx_backpressure_drop','backpressure'),('o_rx_unexpected','unexpected_sequence'),('o_rx_ambiguous_drop','ambiguous_command'),('o_rx_replay_drop','replay_command')]:pre[n]=int(e.reason==r)
            pre['o_issue_ready']=1;pre['o_issue_accept']=i['i_flit_request']
            if i['i_flit_request']:
                self.group+=i['i_new_group'];selected=s.send(codeword_group=self.group,payload=data.to_bytes(self.width//8,'little') if i['i_payload'] else None);self.slot=selected
                if selected.accepted_input:self.memory[self.write]=s.tx.buffer[-1];self.write=(self.write+1)%self.depth
                pre.update(o_payload_accept=int(selected.accepted_input),o_issue_payload=int(selected.payload is not None),o_issue_replay=int(selected.replayed),o_issue_first=int(selected.first_replay),o_issue_sequence=selected.sequence,o_issue_header=selected.header,o_issue_header_valid=1)
            else:self.slot=None
        pre['o_rx_effective_sequence']=s.rx.state.last_sequence if active else oldrx
        pre_rxdata=rxdata if event and event.deliver_payload else 0
        post=self.states();out,postdata=self.pipe(active);post.update(out)
        return [packed,data,rxdata]+[pre[n] for n,w in self.scalar]+[predata,pre_rxdata]+[post[n] for n in self.postnames]+[postdata]
