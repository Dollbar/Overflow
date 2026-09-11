"""Run python3 verification/upli_fifo_payload/replay_fault.py --label FAULT_RUN.
Replay the actual SAT external inputs on healthy and mutated FIFO/SRAM RTL in
Icarus. Write replay/tb.sv, inputs.json, compile.log, run.log and evidence.json.
Next audit the healthy induction matrix; replay does not prove general behavior.
"""
import argparse
import json
from pathlib import Path

from run_formal import ROOT, dump, execute, need, sha


def samples(signal):
    data = iter(signal.get('data', []))
    values = []
    previous = None
    for symbol in signal['wave']:
        if symbol == '=' or (symbol == '4' and 'data' in signal):
            value = next(data)
            previous = int(value, 2) if value else None
        elif symbol in '01':
            previous = int(symbol)
        elif symbol == '4':
            previous = None
        else:
            need(symbol == '.', 'unsupported witness waveform')
        values.append(previous)
    need(values[0] is None and all(v is not None for v in values[1:]), 'incomplete external witness')
    return values[1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    stage = ROOT / 'build/verification/upli_fifo_payload' / args.label
    result = json.loads((stage / 'results.json').read_text())
    need(result['complete'] and result['fault'] in ('head', 'reservation'), 'not a completed actual fault')
    need(len(result['results']) == 1, 'replay expects one configuration')
    row = result['results'][0]
    need((row['width'], row['depth'], row['raw']) == (8, 3, 0), 'unsupported replay configuration')
    source = stage / 'w8_d3_raw0'
    witness = source / 'witness.json'
    signals = {s['name']: s for s in json.loads(witness.read_text())['signal']}
    names = ['i_rstn', 'i_write_valid', 'i_write_data', 'i_read_ready']
    inputs = {n: samples(signals[n]) for n in names}
    cycles = len(inputs[names[0]])
    need(all(len(v) == cycles for v in inputs.values()) and inputs['i_rstn'][0] == 0, 'missing reset/unequal witness lengths')
    folder = stage / 'replay'
    folder.mkdir(exist_ok=False)
    dump(folder / 'inputs.json', inputs)
    (folder / 'runner.py').write_bytes(Path(__file__).read_bytes())
    fifo = ROOT / 'rtl/upli/upli_receive_fifo.v'
    need(result['sources'][str(fifo)] == sha(fifo), 'healthy FIFO changed')
    mutant = (stage / fifo.name).read_text()
    mutation = result['mutation']
    need(fifo.read_text().count(mutation['old']) == 1 and
         mutant == fifo.read_text().replace(mutation['old'], mutation['new']), 'wrong actual mutation')
    (folder / 'healthy.v').write_bytes(fifo.read_bytes())
    (folder / 'mutant.v').write_text(mutant.replace('module upli_receive_fifo #(', 'module faulty_fifo #('))
    composition = (source / 'composition.sv').read_text()
    (folder / 'healthy.sv').write_text(composition)
    (folder / 'mutant.sv').write_text(composition.replace('module fifo_memory(', 'module faulty_memory(').replace('upli_receive_fifo #(', 'faulty_fifo #('))
    text = '''`timescale 1ns/1ps
module tb;
reg clk=0,rstn=0,wvalid=0,ready=0;reg[7:0] data=0;
wire wr,rv,fwr,frv;wire[7:0] rd,frd;wire[1:0] count,fcount;
fifo_memory good(clk,rstn,wvalid,ready,data,wr,rv,rd,count);
faulty_memory bad(clk,rstn,wvalid,ready,data,fwr,frv,frd,fcount);
reg[7:0] queue[0:2];integer n=0,k,cycle=0,detected=0;reg started=0,push,pop;
task step;
begin
 #2;
 if(started)begin
  if(count!==n || wr!==(rstn&&(n<3)))$fatal(1,"healthy occupancy mismatch");
  if(rv && (n==0 || rd!==queue[0]))$fatal(1,"healthy payload mismatch");
  FAULT_CHECK
 end
 push=rstn&&wvalid&&(n<3);pop=rstn&&ready&&rv;
 if(!rstn)n=0;
 else begin
  if(pop)begin for(k=0;k<2;k=k+1)queue[k]=queue[k+1];n=n-1;end
  if(push)begin queue[n]=data;n=n+1;end
 end
 clk=1;#2;clk=0;started=1;cycle=cycle+1;
end
endtask
initial begin
'''
    check = ('if(frv && n>0 && frd!==queue[0])begin detected=detected+1;$display("FAULT payload cycle=%0d actual=%h expected=%h",cycle,frd,queue[0]);end'
             if result['fault'] == 'head' else
             'if(({1\'b0,bad.Fifo_Inst.cnt_cached}+bad.Fifo_Inst.reg_pending)>3\'d2)begin detected=detected+1;$display("FAULT reservation cycle=%0d",cycle);end')
    text = text.replace('FAULT_CHECK', check)
    for i in range(cycles):
        text += f"rstn={inputs['i_rstn'][i]};wvalid={inputs['i_write_valid'][i]};data=8'd{inputs['i_write_data'][i]};ready={inputs['i_read_ready'][i]};step;\n"
    text += 'if(detected==0)$fatal(1,"SAT fault did not replay");$display("PASS actual SAT replay detections=%0d",detected);$finish;end\nendmodule\n'
    (folder / 'tb.sv').write_text(text)
    files = [folder / n for n in ('healthy.v', 'mutant.v', 'healthy.sv', 'mutant.sv', 'tb.sv')]
    files.append(stage / 'kd28_sram_sdp_model.v')
    compile_run = execute(['iverilog', '-g2012', '-s', 'tb', '-o', str(folder / 'sim')] + [str(p) for p in files], folder / 'compile.log', 30)
    need(compile_run['exit'] == 0, 'replay compilation failed')
    run = execute(['vvp', str(folder / 'sim')], folder / 'run.log', 30)
    need(run['exit'] == 0 and 'PASS actual SAT replay' in (folder / 'run.log').read_text(), 'replay failed')
    dump(folder / 'evidence.json', dict(complete=True, fault=result['fault'], cycles=cycles,
         compile=compile_run, run=run, hashes={str(p): sha(p) for p in files + [witness, folder/'inputs.json', folder/'run.log']},
         actual_external_sat_inputs=True, healthy_queue_checked=True, full_goal_complete=False))
    print((folder / 'run.log').read_text())


if __name__ == '__main__':
    main()
