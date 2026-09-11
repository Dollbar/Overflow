`timescale 1ns/1ps
module tb;
parameter CAPACITY=4;
reg clk=0;always #5 clk=~clk;
reg rstn=0,av=0,sv=0,rv=0,cr=0,aw=0,rw=0,last=0,poison=0;
reg [1:0] ap=0,sp=0,rp=0,an=0,nb=0,off=0;
reg [10:0] at=0,st=0,rt=0;reg [9:0] dst=10'h301;
reg [3:0] status=0;reg [255:0] mask=0;reg [511:0] data=0;
wire ar,rr,cv,cdv,cw,err;wire [1:0] cp;wire [10:0] ct;wire [3:0] cs;
wire [511:0] cd;wire [2047:0] full;wire [255:0] cm;wire [7:0] count;
endpoint_tag_table #(.CAPACITY(CAPACITY),.NUM_PORTS(4),.WRITE_ENABLE(1)
`ifndef LEGACY_RED
,.FULL_READ_ENABLE(1)
`endif
) dut(.i_clk(clk),.i_rstn(rstn),.i_local_id(10'h301),
.i_allocate_valid(av),.i_allocate_port(ap),.i_allocate_tag(at),.o_allocate_ready(ar),
.i_sent_valid(sv),.i_sent_port(sp),.i_sent_tag(st),.i_response_valid(rv),.o_response_ready(rr),
.i_response_port(rp),.i_response_tag(rt),.i_response_dst(dst),.i_response_status(status),
.i_response_offset(off),.i_response_last(last),.i_response_num_beats(nb),.i_response_data(data),.i_response_data_error(poison),
.o_complete_valid(cv),.i_complete_ready(cr),.o_complete_port(cp),.o_complete_tag(ct),.o_complete_status(cs),
.o_complete_data(cd),.o_complete_data_valid(cdv),.o_error(err),.o_count(count),
.i_allocate_is_write(aw),.i_response_is_write(rw),.o_complete_is_write(cw)
`ifndef LEGACY_RED
,.i_allocate_read_num_beats(an),.i_allocate_read_mask(mask),.o_complete_data_full(full),.o_complete_mask(cm)
`endif
);
`ifdef LEGACY_RED
assign full={1536'd0,cd};assign cm=0;
`endif
integer fd,n,op,a,b,c,d,e,f,g,line=0,steps=0,waits,j;
reg [255:0] m;reg [2047:0] value;reg [2323:0] held;
initial begin
 fd=$fopen("events.txt","r");if(!fd)$fatal(1,"READ_TAG_FIXTURE");
 while(!$feof(fd))begin
  n=$fscanf(fd,"%d %d %d %d %d %d %d %d %h %h\n",op,a,b,c,d,e,f,g,m,value);
  if(n!=10)$fatal(1,"READ_TAG_PARSE line=%0d n=%0d",line,n);line=line+1;
  @(negedge clk);av=0;sv=0;rv=0;cr=0;
  case(op)
   0:begin rstn=0;@(posedge clk);#1;if(cv||count)$fatal(1,"READ_TAG_RESET");@(negedge clk);rstn=1;end
   1:begin av=1;ap=a;at=b;aw=c;an=d;mask=m;#1;if(ar!==e[0]||err!==f[0])$fatal(1,"READ_TAG_ALLOC line=%0d ready=%b error=%b",line,ar,err);@(posedge clk);#1;end
   2:begin sv=1;sp=a;st=b;#1;if(err!==c[0])$fatal(1,"READ_TAG_SENT");@(posedge clk);#1;end
   3:begin rv=1;rp=a;rt=b;rw=c;off=d;nb=e;last=f;status=g&15;poison=(g>>4)&1;dst=(g>>5)&1023;data=value[511:0];
    #1;if(!rr||err!==m[0])$fatal(1,"READ_TAG_RESPONSE line=%0d tag=%0d off=%0d nb=%0d last=%0d status=%0d error=%b expected=%b",line,b,d,e,f,status,err,m[0]);@(posedge clk);#1;end
   4:begin // Expected tuple and bytes are precomputed independently of observed DUT values.
    waits=0;while(!cv&&waits<6)begin @(posedge clk);#1;waits=waits+1;end
    if(!cv||{cp,ct,cw,cs,cdv}!=={a[1:0],b[10:0],c[0],d[3:0],e[0]})$fatal(1,"READ_TAG_COMPLETE_ID line=%0d",line);
    if(full!==value||cm!==m||cd!==value[511:0])$fatal(1,"READ_TAG_COMPLETE_BYTES line=%0d",line);
    held={cv,cp,ct,cw,cs,cdv,cm,full};
    repeat(3)begin @(posedge clk);#1;if({cv,cp,ct,cw,cs,cdv,cm,full}!==held)$fatal(1,"READ_TAG_HOLD");end
    @(negedge clk);cr=1;@(posedge clk);#1;steps=steps+1;
   end
   5:begin repeat(3)begin @(posedge clk);#1;if(cv||count!==a[7:0])$fatal(1,"READ_TAG_EARLY_DONE line=%0d count=%0d",line,count);end end
   default:$fatal(1,"READ_TAG_OPCODE");
  endcase
 end
 $display("READ_TAG_PASS capacity=%0d completions=%0d events=%0d",CAPACITY,steps,line);$finish;
end
initial begin #5000000;$fatal(1,"READ_TAG_TIMEOUT");end
endmodule
