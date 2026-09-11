"""Run: python3 verification/tl_tx_channels/run_rtl.py [--label unit] [--replace FILE].
Actual class-selection and ownership cycle vectors; next dual actual SRAM peers.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,subprocess
from test_model import Channels,inputs
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='unit');p.add_argument('--replace',type=Path);a=p.parse_args();S=R/'build/verification/tl_tx_channels'/a.label;S.mkdir(parents=True,exist_ok=False)
src=[R/'rtl/tl'/n for n in ('tl_tx_channels.v','tl_tx_packer.v','tl_tx_packer_core.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')]
if a.replace:src=[a.replace if x.name==a.replace.name else x for x in src]
def pack(v,b):return sum(int(x)<<(j*b) for j,x in enumerate(v))
rows=[]
for width in (8,16):
    B=S/f'w{width}';B.mkdir();spec=[('rstn',1),('taken',1),('pending',7),('auth',1),('done',1),('shared',1),('available',20*(width+1)),('capacity',20*(width+1)),('request_budget',3),('response_budget',4),('header_valid',2),('headers',512),('tags_valid',2),('tags',512),('data_valid',4),('data0',512),('data1',512),('fc_valid',1),('fc_flit',512),('fc_msg',2)];offset={};pos=0
    for k,b in spec:offset[k]=(pos,b);pos+=b
    model=Channels();vectors=[];answers=[]
    def add(x,transfer=True,reset=False):
        out=model.step(**x,transfer=transfer,reset=reset);s=x['sources'];v=dict(x,rstn=not reset,taken=transfer,fc_flit=x['fc'],header_valid=pack([z['valid'] for z in s],1),headers=pack([z['header'] for z in s],256),tags_valid=pack([z['tags_valid'] for z in s],1),tags=pack([z['tags'] for z in s],256),data_valid=pack([z['data_valid'] for z in s],2),data0=pack([z['data0'] for z in s],256),data1=pack([z['data1'] for z in s],256),available=pack(x['available'],width+1),capacity=pack(x['capacity'],width+1))
        vectors.append(sum(int(v[k])<<offset[k][0] for k,b in spec));answers.append(int(out['valid'])|(out['flit']<<1)|(out['msg']<<513)|(out['header_taken']<<515)|(out['tags_taken']<<517)|(pack(out['data_taken'],2)<<519)|(int(out['fc_taken'])<<523)|(out['header_error']<<524)|(out['capacity_shortfall']<<526))
    for pending,auth,fc,blocked,gap in itertools.product((0,1,2,73),(False,True),(False,True),(None,0,1),(None,0,1)):
        x=inputs(pending=pending,auth=auth,fc_valid=fc)
        if blocked is not None:x['available'][11+5*blocked]=0
        if gap is not None:x['sources'][gap]['data_valid']=0
        add(x,reset=True);add(x,False);add(x,False);add(x)
    for first in (0,1):
        x=inputs();x['sources'][1-first]['valid']=False;add(x,reset=True);add(x,False);add(inputs(),False);add(inputs())
        x=inputs(pending=1);add(x,False);add(x);add(inputs(pending=6));add(inputs(pending=2));add(inputs(pending=0))
    for field in ('request_budget','response_budget'):
        x=inputs(**{field:0});add(x,reset=True);add(x)
    for lane in (0,1):
        x=inputs();x['sources'][lane]['header']=x['sources'][1-lane]['header'];add(x,reset=True);add(x)
        x=inputs();x['capacity'][11+5*lane]=1;x['available'][11+5*lane]=1;add(x,reset=True);add(x)
    x=inputs(response_budget=1);x['available'][11]=0;x['sources'][1]['header']=sum((5<<28)<<(32*j) for j in range(4));add(x,reset=True);add(x)
    add(inputs(),reset=True)
    for _ in range(20):add(inputs())
    (B/'vectors.hex').write_text('\n'.join(f'{v:0{(pos+3)//4}x}' for v in vectors)+'\n');(B/'expected.hex').write_text('\n'.join(f'{v:0132x}' for v in answers)+'\n')
    connections=','.join(f'.i_{k}(v[{o}+:{b}])' for k,(o,b) in offset.items());tb=f'''module tb;
reg clk=0;always #5 clk=~clk;reg [{pos-1}:0] v,vectors[0:{len(vectors)-1}];reg [527:0] expected[0:{len(vectors)-1}];wire [527:0] actual;integer j;
tl_tx_channels #(.WIDTH({width})) dut(.i_clk(clk),{connections},.o_valid(actual[0]),.o_flit(actual[1+:512]),.o_msg(actual[513+:2]),.o_header_taken(actual[515+:2]),.o_tags_taken(actual[517+:2]),.o_data_taken(actual[519+:4]),.o_fc_taken(actual[523]),.o_header_error(actual[524+:2]),.o_capacity_shortfall(actual[526+:2]));
initial begin $readmemh("{B}/vectors.hex",vectors);$readmemh("{B}/expected.hex",expected);
for(j=0;j<{len(vectors)};j=j+1)begin @(negedge clk);v=vectors[j];#1;if(actual!==expected[j])$fatal(1,"channels vector %0d actual=%h expected=%h",j,actual,expected[j]);end
@(negedge clk);$display("PASS channels WIDTH={width} vectors={len(vectors)}");$finish;end
endmodule
'''
    (B/'tb.sv').write_text(tb);c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,vectors=len(vectors),compile_exit=c.returncode,passed=False)
    if not c.returncode:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS channels' in c.stdout);print(c.stdout,flush=True)
    rows.append(row)
(S/'results.json').write_text(json.dumps(dict(results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src if f.exists()}),indent=2)+'\n');raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
