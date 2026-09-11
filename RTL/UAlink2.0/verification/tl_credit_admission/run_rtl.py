"""Run: python3 verification/tl_credit_admission/run_rtl.py [--label NAME] [--replace FILE].
Writes actual HDL vectors/logs/results under build/verification/tl_credit_admission.
Next: exercise the admitted port in the actual dual SRAM regression.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess
from test_model import fixtures
R=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='guard');p.add_argument('--replace',type=Path);a=p.parse_args()
S=R/'build/verification/tl_credit_admission'/a.label;S.mkdir(parents=True,exist_ok=False)
sources=[R/'rtl/tl'/f for f in ('tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')]
if a.replace:sources=[a.replace if f.name==a.replace.name else f for f in sources]
def pack(v,b):return sum(x<<(i*b) for i,x in enumerate(v))
rows=[]
for width in (8,16):
    B=S/f'w{width}';B.mkdir();vectors=[];answers=[];bits=20*(width+1)
    for word,logical in fixtures():
        for shared in (0,1):
            need=list(logical)
            if shared:need[10]+=need[15];need[15]=0
            for mode in range(8):
                cap=[max(8,n) for n in need];av=cap.copy();control=1;done=1;rstn=1;want=need.copy();allow=1;wait=0;short=0
                used=next((j for j,n in enumerate(need) if n),None)
                if mode in (1,2) and used is not None:
                    av[used]=need[used]-1;allow=0
                    if mode==1:wait=1
                    else:cap[used]=av[used];short=1
                if mode==3:done=0;cap=[0]*20;av=cap.copy();allow=int(not any(need));wait=1-allow
                if mode==4:control=0;want=[0]*20
                if mode==5:rstn=0;want=[0]*20;allow=0
                if mode==7:done=0;allow=int(not any(need));wait=1-allow
                if mode==6:cap=[(1<<(width+1))-1]*20;av=cap.copy()
                inp=word|(control<<256)|(shared<<257)|(done<<258)|(rstn<<259)|(pack(av,width+1)<<260)|(pack(cap,width+1)<<(260+bits))
                vectors.append(inp);answers.append(pack(want,6)|(allow<<120)|(wait<<121)|(short<<122))
    for word in (6<<28,15<<252,1<<28):
        vectors.append(word|(1<<256)|(1<<258)|(1<<259));answers.append(0)
    (B/'vectors.hex').write_text('\n'.join(f'{x:0{(260+2*bits+3)//4}x}' for x in vectors)+'\n');(B/'expected.hex').write_text('\n'.join(f'{x:031x}' for x in answers)+'\n')
    tb=f'''module tb;
reg [{259+2*bits}:0] inputs[0:{len(vectors)-1}];reg [122:0] expected[0:{len(vectors)-1}];
reg [{259+2*bits}:0] v;wire [119:0] req;wire allow,waiting,shortfall;integer i;
tl_credit_admission #(.WIDTH({width})) dut(.i_half(v[255:0]),.i_control(v[256]),.i_shared(v[257]),.i_done(v[258]),.i_rstn(v[259]),.i_available(v[260+:{bits}]),.i_capacity(v[{260+bits}+:{bits}]),.o_requirements(req),.o_allow(allow),.o_wait(waiting),.o_shortfall(shortfall));
initial begin
$readmemh("{B}/vectors.hex",inputs);$readmemh("{B}/expected.hex",expected);
for(i=0;i<{len(vectors)};i=i+1)begin v=inputs[i];#1;if({{shortfall,waiting,allow,req}}!==expected[i])$fatal(1,"admission vector %0d actual=%h expected=%h",i,{{shortfall,waiting,allow,req}},expected[i]);end
$display("PASS admission WIDTH={width} vectors={len(vectors)}");$finish;end
endmodule
'''
    (B/'tb.sv').write_text(tb);cmd=['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,sources),str(B/'tb.sv')]
    c=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,vectors=len(vectors),compile_exit=c.returncode,passed=False)
    if c.returncode==0:
        x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(x.stdout+x.stderr);print(x.stdout,flush=True);row.update(run_exit=x.returncode,passed=x.returncode==0 and 'PASS admission' in x.stdout)
    rows.append(row)
(S/'results.json').write_text(json.dumps(dict(results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources if f.exists()}),indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
