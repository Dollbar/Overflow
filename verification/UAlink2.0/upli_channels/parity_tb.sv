`timescale 1ns/1ps
module tb;
parameter KIND=0;
reg check_enable,valid;
reg [67:0] controls;
reg [56:0] address;
reg [63:0] auth,be;
reg [511:0] data;
reg [3:0] credit_valid,credit_pool;
reg [7:0] credit_vc,credit_num;
reg [14:0] received,expected_parity,expected_errors;
wire [14:0] parity,errors;
wire control_error,data_error,auth_error;
reg expected_control,expected_data,expected_auth;
integer fd,n,count=0;
upli_parity #(.CHANNEL_KIND(KIND)) dut(
 .i_check_enable(check_enable),.i_valid(valid),.i_control(controls),
 .i_address(address),.i_auth(auth),.i_data(data),.i_byte_enable(be),
 .i_credit_valid(credit_valid),.i_credit_pool(credit_pool),
 .i_credit_vc(credit_vc),.i_credit_num(credit_num),.i_received_parity(received),
 .o_parity(parity),.o_errors(errors),.o_control_error(control_error),
 .o_data_error(data_error),.o_auth_error(auth_error));
initial begin
 fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"PARITY_FILE");
 while(!$feof(fd))begin
  n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
   check_enable,valid,controls,address,auth,data,be,credit_valid,credit_pool,
   credit_vc,credit_num,received,expected_parity,expected_errors,
   expected_control,expected_data,expected_auth);
  if(n!=17)$fatal(1,"PARITY_VECTOR");
  #1;
  if({parity,errors,control_error,data_error,auth_error}!==
     {expected_parity,expected_errors,expected_control,expected_data,expected_auth})
    $fatal(1,"PARITY_MISMATCH kind=%0d row=%0d parity=%h/%h errors=%h/%h",KIND,count,parity,expected_parity,errors,expected_errors);
  count=count+1;
 end
 if(count<1000)$fatal(1,"PARITY_COVERAGE");
 $display("PARITY_PASS kind=%0d vectors=%0d",KIND,count);$finish;
end
endmodule
