"""Run python3 verification/tl_control_partition/run_rtl.py [--label unit] [--replace FILE] [--dependency-root DIR].
Outputs actual two-width partition/cursor/tag vectors. Next real buffered dual peers.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,random,subprocess,sys
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from control_partition import Partitioner
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='unit');p.add_argument('--replace',type=Path);p.add_argument('--dependency-root',type=Path);a=p.parse_args();S=R/'build/verification/tl_control_partition'/a.label;S.mkdir(parents=True,exist_ok=False)
src=[R/'rtl/tl/tl_control_partition.v']+[(a.dependency_root or R/'rtl/tl')/n for n in ('tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')]
if a.replace:src=[a.replace if x.name==a.replace.name else x for x in src]
def pack(v,b):return sum(int(x)<<(j*b) for j,x in enumerate(v))
rows=[]
for width in (8,16):
    B=S/f'w{width}';B.mkdir();model=Partitioner();vectors=[];answers=[];spec=[('rstn',1),('source_valid',1),('ready',1),('done',1),('response',1),('auth',1),('shared',1),('source_control',256),('source_tags',512),('capacity',20*(width+1))];offset={};pos=0
    for k,b in spec:offset[k]=(pos,b);pos+=b
    def add(word,tags,caps,*,response=True,auth=False,shared=False,valid=True,ready=True,done=True,reset=False):
        out=model.step(word,tags,caps,response=response,auth=auth,shared=shared,valid=valid,ready=ready,done=done,reset=reset)
        v=dict(rstn=not reset,source_valid=valid,ready=ready,done=done,response=response,auth=auth,shared=shared,source_control=word,source_tags=tags,capacity=pack(caps,width+1));vectors.append(sum(int(v[k])<<offset[k][0] for k,b in spec));answers.append(int(out['valid'])|(int(out['taken'])<<1)|(int(out['source_taken'])<<2)|(int(out['error'])<<3)|(int(out['shortfall'])<<4)|(out['word']<<5)|(out['tags']<<261)|(out['fields']<<517)|(out['end']<<521)|(out['cursor']<<525));return out
    rng=random.Random(3419)
    for response,auth,shared,cap in itertools.product((False,True),(False,True),(False,True),(0,1,2,4,8)):
        caps=[cap]*20;caps[15]=0 if shared else cap
        for case in range(12):
            if response:
                kind=(2,4,5)[case%3];n=(4 if kind==2 else 8);words=[]
                for j in range(n):
                    vc=j%4;pool=(case//3)%2
                    if kind==2:word=(2<<60)|(vc<<58)|(pool<<46)|((case%4)<<44)|(1<<37)|(j<<47)
                    elif kind==4:word=(4<<28)|(vc<<26)|(pool<<14)|(j<<15)
                    else:word=(5<<28)|(vc<<26)|(pool<<14)|(j<<15)|((case%4)<<2)|((case%2)<<1)
                    words.append(word)
                word=pack(words,64 if kind==2 else 32)
            else:
                kind=1 if case%2 else 3
                if kind==1:word=pack([(1<<124)|((0x23 if case%3 else 0x26)<<118)|(j<<116)|((case%4)) for j in range(2)],128)
                else:word=pack([(3<<60)|((case%8)<<57)|(j<<55)|((case%4)<<39) for j in range(4)],64)
            tags=pack([rng.getrandbits(64) for _ in range(8)],64);kw=dict(response=response,auth=auth,shared=shared)
            add(word,tags,caps,reset=True,**kw);add(word,tags,caps,done=False,**kw)
            for _ in range(10):
                add(word,tags,caps,ready=False,**kw);out=add(word,tags,caps,**kw)
                if out['source_taken'] or not out['valid']:break
    for word,response in [((2<<60)|(1<<37),False),((2<<60)|(1<<37)|(1<<64),True),(6<<28,True),(0,True)]:
        add(word,0,[8]*20,reset=True,response=response);add(word,0,[8]*20,response=response)
    word=pack([(2<<60)|(1<<37)|(j<<47) for j in range(4)],64)
    add(word,1,[1]*20,reset=True);add(word,1,[1]*20);add(word,1,[1]*20,reset=True);add(word,1,[1]*20)
    (B/'vectors.hex').write_text('\n'.join(f'{v:x}' for v in vectors)+'\n');(B/'expected.hex').write_text('\n'.join(f'{v:x}' for v in answers)+'\n');connections=','.join(f'.i_{k}(v[{o}+:{b}])' for k,(o,b) in offset.items())
    tb=f'''module tb;
reg clk=0;always #5 clk=~clk;reg [{pos-1}:0] v,vectors[0:{len(vectors)-1}];reg [528:0] expected[0:{len(vectors)-1}];wire [528:0] actual;integer j;
tl_control_partition #(.WIDTH({width})) dut(.i_clk(clk),{connections},.o_valid(actual[0]),.o_taken(actual[1]),.o_source_taken(actual[2]),.o_error(actual[3]),.o_shortfall(actual[4]),.o_control(actual[5+:256]),.o_tags(actual[261+:256]),.o_fields(actual[517+:4]),.o_end(actual[521+:4]),.o_cursor(actual[525+:4]));
initial begin $readmemh("{B}/vectors.hex",vectors);$readmemh("{B}/expected.hex",expected);for(j=0;j<{len(vectors)};j=j+1)begin @(negedge clk);v=vectors[j];#1;if(actual!==expected[j])$fatal(1,"partition vector %0d actual=%h expected=%h",j,actual,expected[j]);end @(negedge clk);$display("PASS partition WIDTH={width} vectors={len(vectors)}");$finish;end
endmodule
''';(B/'tb.sv').write_text(tb);c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,vectors=len(vectors),compile_exit=c.returncode,passed=False)
    if c.returncode==0:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS partition' in c.stdout);print(c.stdout,flush=True)
    rows.append(row)
(S/'results.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src if f.exists()}),indent=2)+'\n');raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
