"""Check full ordinary Read geometry, all ATTR masks and raw encoding.
Run: python3 verification/endpoint_transaction/run_read_encode.py --label NEW [--baseline]
Outputs immutable source/TB snapshots, compile/run logs and result.json under build/verification/endpoint_transaction/NEW.
Next connect the same N/mask contract to actual backend and shared completion ownership.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
TB=r'''`timescale 1ns/1ps
module tb;
reg valid=1;reg [56:0] address=0;reg [5:0] length=0;reg [7:0] attr=0;
reg [1:0] vc=0,asi=3;reg pool=0;reg [7:0] metadata=8'h9c;
wire ok,error;wire [255:0] control,be;wire [1:0] beats;
`ifdef BASELINE
endpoint_read_encode dut(
`else
endpoint_read_encode #(.FULL_READ_ENABLE(1)) dut(.o_num_beats(beats),.o_be(be),
`endif
 .i_valid(valid),.i_tag(11'h401),.i_src(10'd17),.i_dst(10'd513),.i_address(address),.i_length(length),.i_attr(attr),.i_vc(vc),.i_pool(pool),.i_asi(asi),.i_metadata(metadata),.o_valid(ok),.o_error(error),.o_control(control));
integer off,l,a,b,k,n,good=0,bad=0;reg [255:0] expected;reg [127:0] literal;
initial begin
 address=(57'd1<<56)+57'd60;length=1;attr=8'ha5;#1;
 // Separate fixed raw literal is supplied below by the retained generator.
 literal=FIXED_LITERAL;
 if(ok!==1'b1||error!==1'b0)$fatal(1,"READ_ENCODE_CAPABILITY");
 if(control!=={128'd0,literal})$fatal(1,"READ_ENCODE_LITERAL got=%h exp=%h",control,literal);
 for(off=0;off<64;off=off+1)for(l=0;l<64;l=l+1)for(a=0;a<256;a=a+1)begin
  address=(57'd1<<56)+off*4;length=l;attr=a;#1;
  if(off+l+1<=64)begin
   if(ok!==1'b1||error!==1'b0)$fatal(1,"READ_ENCODE_REJECT off=%0d len=%0d attr=%h",off,l,a);
   n=((off%16)*4+4*(l+1)+63)/64;
   expected=0;
   // Oracle builds whole DWORDs, then applies only the two boundary nibbles.
   for(k=off;k<=off+l;k=k+1)expected[k*4+:4]=4'hf;
   expected[off*4+:4]=a[3:0];if(l!=0)expected[(off+l)*4+:4]=a[7:4];
   if(be!==expected||beats!==n-1)$fatal(1,"READ_ENCODE_MASK off=%0d len=%0d attr=%h be=%h expected=%h",off,l,a,be,expected);
   if(control[127:124]!==4'd1||control[123:118]!==6'd3||control[115:114]!==asi||control[113:103]!==11'h401||control[101:94]!==attr||control[93:88]!==length||control[87:80]!==metadata||{control[79:25],2'b00}!==address||control[24:15]!==10'd17||control[14:5]!==10'd513||control[4:0]!==5'd0||control[255:128]!==128'd0)$fatal(1,"READ_ENCODE_FIELDS");
   good=good+1;
  end else begin if(ok!==1'b0||error!==1'b1||control!==0||be!==0)$fatal(1,"READ_ENCODE_CROSS_REGION");bad=bad+1;end
 end
 address=0;length=0;attr=0;
 for(b=1;b<4;b=b+1)begin address=b;#1;if(ok!==0||error!==1)$fatal(1,"READ_ENCODE_ALIGNMENT");end
 address=0;vc=1;#1;if(ok!==0||error!==1)$fatal(1,"READ_ENCODE_VC");vc=0;pool=1;#1;if(ok!==0||error!==1)$fatal(1,"READ_ENCODE_POOL");valid=0;#1;if(ok!==0||error!==0)$fatal(1,"READ_ENCODE_IDLE");
 $display("READ_ENCODE_PASS good=%0d bad=%0d",good,bad);$finish;
end
endmodule
'''
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--baseline',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label required')
 stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
 src=ROOT/'rtl/endpoint/endpoint_read_encode.v';raw=src.read_bytes();(stage/src.name).write_bytes(raw)
 literal=(1<<124)|(3<<118)|(3<<114)|(0x401<<103)|(0xa5<<94)|(1<<88)|(0x9c<<80)|((((1<<56)+60)>>2)<<25)|(17<<15)|(513<<5)
 tb=TB.replace('FIXED_LITERAL',f"128'h{literal:032x}");(stage/'tb.sv').write_text(tb);(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
 result={'passed':False,'baseline':a.baseline,'sources':{str(src):hashlib.sha256(raw).hexdigest(),str(Path(__file__)):hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}}
 c=['iverilog','-g2012','-s','tb']+(['-DBASELINE'] if a.baseline else [])+['-o',str(stage/'sim.vvp'),str(stage/'tb.sv'),str(stage/src.name)]
 for phase,cmd in [('compile',c),('run',['vvp',str(stage/'sim.vvp')])]:
  result[phase+'_command']=cmd
  with (stage/(phase+'.log')).open('w') as f:
   try:code=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=600).returncode
   except subprocess.TimeoutExpired:code=124
  result[phase+'_exit']=code
  if phase=='compile' and code:break
 log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
 result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==0 and 'READ_ENCODE_PASS' in log
 result['expected_red']=a.baseline and result.get('compile_exit')==0 and result.get('run_exit')==1 and 'READ_ENCODE_CAPABILITY' in log
 result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print({k:result[k] for k in ('passed','expected_red','compile_exit','run_exit') if k in result});return 0 if result['passed'] or result['expected_red'] else 1
if __name__=='__main__':raise SystemExit(main())
