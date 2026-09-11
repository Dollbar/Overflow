`timescale 1ns/1ps
module role_fault_tb;
parameter PORTS=1,ROLES=1,IS_TL=0;
reg clk=0;always #5 clk=~clk;
reg rstn=0;
reg [ROLES-1:0] ack=0,init_done=0;
reg [3:0] control_error=0,credit_error=0,auth_error=0,profile_error=0,metadata_error=0,order_error=0,storage_error=0,tdm_error=0,data_error=0;
wire [ROLES-1:0] drop_roles,notify_roles,ack_accepted,reset_required,init_incomplete;
wire [ROLES*PORTS-1:0] drop_ports;
wire [31:0] reasons;
wire [3:0] observed_data;
upli_rx_role_fault_controller #(.C_NUM_PORTS(PORTS),.C_NUM_ROLES(ROLES),.C_IS_TL(IS_TL)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_fault_ack(ack),.i_init_done_roles(init_done),
 .i_control_error(control_error),.i_credit_control_error(credit_error),.i_auth_error(auth_error),.i_auth_profile_error(profile_error),
 .i_metadata_error(metadata_error),.i_order_error(order_error),.i_storage_error(storage_error),.i_tdm_error(tdm_error),.i_data_error(data_error),
 .o_drop_roles(drop_roles),.o_drop_ports(drop_ports),.o_notify_roles(notify_roles),.o_ack_accepted(ack_accepted),.o_reset_required(reset_required),
 .o_reason_sticky(reasons),.o_init_incomplete(init_incomplete),.o_data_error_observed(observed_data));
integer fd,rc,rows,index;
reg [1023:0] path;
reg [ROLES-1:0] e_drop,e_notify,e_ack,e_reset,e_init,p_drop,p_notify,p_ack,p_reset,p_init;
reg [ROLES*PORTS-1:0] e_ports,p_ports;
reg [31:0] e_reasons,p_reasons;
reg [3:0] e_data,p_data;
initial begin
 if(!$value$plusargs("VECTORS=%s",path)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"ARGS");
 fd=$fopen(path,"r");if(!fd)$fatal(1,"OPEN");
 @(posedge clk);#1;
 for(index=0;index<rows;index=index+1)begin
  @(negedge clk);
  rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,ack,init_done,control_error,credit_error,auth_error,profile_error,metadata_error,order_error,storage_error,tdm_error,data_error,e_drop,e_ports,e_notify,e_ack,e_reset,e_reasons,e_init,e_data,p_drop,p_ports,p_notify,p_ack,p_reset,p_reasons,p_init,p_data);
  if(rc!=28)$fatal(1,"PARSE row=%0d rc=%0d",index,rc);
  #1;if({drop_roles,drop_ports,notify_roles,ack_accepted,reset_required,reasons,init_incomplete,observed_data}!=={e_drop,e_ports,e_notify,e_ack,e_reset,e_reasons,e_init,e_data})$fatal(1,"ROLE_PRE row=%0d got=%h expected=%h",index,{drop_roles,drop_ports,notify_roles,ack_accepted,reset_required,reasons,init_incomplete,observed_data},{e_drop,e_ports,e_notify,e_ack,e_reset,e_reasons,e_init,e_data});
  @(posedge clk);#1;if({drop_roles,drop_ports,notify_roles,ack_accepted,reset_required,reasons,init_incomplete,observed_data}!=={p_drop,p_ports,p_notify,p_ack,p_reset,p_reasons,p_init,p_data})$fatal(1,"ROLE_POST row=%0d",index);
 end
 $display("ROLE_PASS ports=%0d roles=%0d tl=%0d rows=%0d",PORTS,ROLES,IS_TL,rows);$finish;
end
endmodule
