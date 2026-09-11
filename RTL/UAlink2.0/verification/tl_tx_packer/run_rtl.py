"""Run: python3 verification/tl_tx_packer/run_rtl.py [--label NAME] [--replace FILE].
Outputs real cycle tests under build/verification/tl_tx_packer; next actual dual peers.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,random,subprocess,sys
from test_model import Packer,inputs
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='unit');p.add_argument('--replace',type=Path);a=p.parse_args();S=R/'build/verification/tl_tx_packer'/a.label;S.mkdir(parents=True,exist_ok=False)
src=[R/'rtl/tl'/n for n in ('tl_tx_packer.v','tl_tx_packer_core.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')]
if a.replace:src=[a.replace if q.name==a.replace.name else q for q in src]
keys=[('rstn',1),('transfer',1),('pending',7),('auth',1),('done',1),('shared',1),('available',None),('capacity',None),('request_budget',3),('response_budget',4),('header_valid',1),('header',256),('tags_valid',1),('tags',256),('data_valid',2),('data0',256),('data1',256),('fc_valid',1),('fc',512),('fc_msg',2)]
def pack(v,b):return sum(x<<(j*b) for j,x in enumerate(v))
rows=[]
for w in (8,16):
    B=S/f'w{w}';B.mkdir();spec=[(k,20*(w+1) if b is None else b) for k,b in keys];offset={};pos=0
    for k,b in spec:offset[k]=(pos,b);pos+=b
    model=Packer();vectors=[];answers=[]
    def add(x,transfer=True,reset=False):
        y=model.step(**x,transfer=transfer,reset=reset);v=0;values=dict(x,rstn=not reset,transfer=transfer)
        for k,b in spec:
            n=pack(values[k],w+1) if k in ('available','capacity') else int(values[k]);v|=n<<offset[k][0]
        out=int(y['valid'])|(y['flit']<<1)|(y['msg']<<513)|(int(y['header_taken'])<<515)|(int(y['tags_taken'])<<516)|(y['data_taken']<<517)|(int(y['fc_taken'])<<519)
        vectors.append(v);answers.append(out)
    for pending,auth,fc_valid,fc_msg,dv,credit,budget in itertools.product((0,1,2,73),(False,True),(False,True),(0,2),(0,1,2),(False,True),(False,True)):
        x=inputs(pending=pending,auth=auth,fc_valid=fc_valid,fc_msg=fc_msg,fc=(1<<256) if fc_msg else 1<<22,data_valid=dv,available=[8 if credit else 0]*20,request_budget=4 if budget else 0)
        add(x,reset=True);add(x,False);add(x,False);add(x,True)
    # FC/header arrivals may change while the selected, unconsumed queue stays stable.
    for fcfirst in (False,True):
        x=inputs(fc_valid=fcfirst,header_valid=not fcfirst);add(x,reset=True);add(x,False)
        x=inputs(fc_valid=True);add(x,False);add(x,True)
        for _ in range(20):add(x)
    add(inputs(),reset=True)
    (B/'vectors.hex').write_text('\n'.join(f'{x:0{(pos+3)//4}x}' for x in vectors)+'\n');(B/'expected.hex').write_text('\n'.join(f'{x:0130x}' for x in answers)+'\n')
    ports={'rstn':'i_rstn','transfer':'i_taken','header':'i_header','tags':'i_tags','fc':'i_fc_flit','fc_msg':'i_fc_msg'}
    connections=','.join(f'.{ports.get(k,"i_"+k)}(v[{o}+:{b}])' for k,(o,b) in offset.items())
    tb=f'''module tb;
reg clk=0;always #5 clk=~clk;
reg [{pos-1}:0] vectors[0:{len(vectors)-1}],v;reg [519:0] expected[0:{len(vectors)-1}];wire [519:0] actual;integer j;
tl_tx_packer #(.WIDTH({w})) dut(.i_clk(clk),{connections},.o_valid(actual[0]),.o_flit(actual[1+:512]),.o_msg(actual[513+:2]),.o_header_taken(actual[515]),.o_tags_taken(actual[516]),.o_data_taken(actual[517+:2]),.o_fc_taken(actual[519]),.o_header_wait(),.o_capacity_shortfall());
initial begin $readmemh("{B}/vectors.hex",vectors);$readmemh("{B}/expected.hex",expected);
for(j=0;j<{len(vectors)};j=j+1)begin @(negedge clk);v=vectors[j];#1;if(actual!==expected[j])$fatal(1,"packer vector %0d actual=%h expected=%h",j,actual,expected[j]);end
@(negedge clk);$display("PASS packer WIDTH={w} vectors={len(vectors)}");$finish;end
endmodule
'''
    (B/'tb.sv').write_text(tb);c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=w,vectors=len(vectors),compile_exit=c.returncode,passed=False)
    if not c.returncode:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS packer' in c.stdout);print(c.stdout,flush=True)
    rows.append(row)
(S/'results.json').write_text(json.dumps(dict(results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src if f.exists()}),indent=2)+'\n');raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
