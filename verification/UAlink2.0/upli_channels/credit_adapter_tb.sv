`timescale 1ns/1ps
module credit_adapter_tb;
parameter TEST_GUARD=1,TEST_ADAPTER=1;
reg en;reg [3:0] valid,pool,init;reg [7:0] vc,num;reg vp,cp;
wire [3:0] ov,op,oi;wire [7:0] oc,on;wire ovp,ocp,ve,ce,err,ok;
reg [3:0] ev,ep,ei;reg [7:0] ec,enumber;reg evp,ecp,eve,ece,ee,eo;
integer fd,rc,row;
upli_credit_return_adapter adapter(.i_credit_valid(valid),.i_credit_pool(pool),.i_credit_vc(vc),.i_credit_num(num),.i_credit_init_done(init),.o_credit_valid(ov),.o_credit_pool(op),.o_credit_vc(oc),.o_credit_num(on),.o_credit_init_done(oi),.o_credit_valid_parity(ovp),.o_credit_parity(ocp));
upli_credit_guard guard(.i_check_enable(en),.i_credit_valid(valid),.i_credit_pool(pool),.i_credit_vc(vc),.i_credit_num(num),.i_credit_valid_parity(vp),.i_credit_parity(cp),.o_valid_error(ve),.o_control_error(ce),.o_error(err),.o_integrity_ok(ok));
initial begin
fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"CREDIT_VECTOR_OPEN");row=0;
while(!$feof(fd))begin
 rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",en,valid,pool,vc,num,init,vp,cp,ev,ep,ec,enumber,ei,evp,ecp,eve,ece,ee,eo);
 if(rc==19)begin
  #1;
  if(TEST_ADAPTER&&{ov,op,oc,on,oi,ovp,ocp}!=={ev,ep,ec,enumber,ei,evp,ecp})$fatal(1,"CREDIT_ADAPTER_COMPARE row=%0d actual=%h expected=%h",row,{ov,op,oc,on,oi,ovp,ocp},{ev,ep,ec,enumber,ei,evp,ecp});
  if(TEST_GUARD&&{ve,ce,err,ok}!=={eve,ece,ee,eo})$fatal(1,"CREDIT_GUARD_COMPARE row=%0d actual=%h expected=%h",row,{ve,ce,err,ok},{eve,ece,ee,eo});
  row=row+1;
 end else if(rc!=-1)$fatal(1,"CREDIT_VECTOR_PARSE");
end
$fclose(fd);$display("CREDIT_ADAPTER_PASS rows=%0d guard=%0d adapter=%0d",row,TEST_GUARD,TEST_ADAPTER);$finish;
end
endmodule
