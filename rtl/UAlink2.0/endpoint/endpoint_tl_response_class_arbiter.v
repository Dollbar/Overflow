`timescale 1ns/1ps
`default_nettype none
// 单Logical Port的普通Read、Write与Message响应仲裁。owner从首次展示保持到
// Header及本响应组全部Data实际接纳；只有完成后RR才前进。
module endpoint_tl_response_class_arbiter(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[2:0] i_valid,input wire[767:0] i_control,input wire[5:0] i_port,
 input wire[5:0] i_data_count,input wire[1535:0] i_data,input wire[5:0] i_data_poison,
 output reg[2:0] o_source_captured,output reg[5:0] o_data_accepted,
 output wire o_valid,output wire[255:0] o_control,output wire[1:0] o_port,
 output wire[1:0] o_data_count,output wire[511:0] o_data,output wire[1:0] o_data_poison,
 input wire i_source_captured,input wire[1:0] i_data_accepted,
 output wire[1:0] o_owner_class,output wire o_busy,output wire o_quiescent,output wire o_error
);
reg locked_q,header_q,error_q;reg[1:0] owner_q,next_q,select;reg found;
wire malformed_offer=(i_valid[0]&&(i_data_count[1:0]==2'd3))||(i_valid[1]&&(i_data_count[3:2]==2'd3))||(i_valid[2]&&(i_data_count[5:4]==2'd3));
wire[2:0] eligible={i_valid[2]&&(i_data_count[5:4]!=2'd3),i_valid[1]&&(i_data_count[3:2]!=2'd3),i_valid[0]&&(i_data_count[1:0]!=2'd3)};
always @* begin
 select=owner_q;found=locked_q;
 if(!locked_q)begin
  case(next_q)
   2'd0:if(eligible[0])begin select=0;found=1;end else if(eligible[1])begin select=1;found=1;end else if(eligible[2])begin select=2;found=1;end
   2'd1:if(eligible[1])begin select=1;found=1;end else if(eligible[2])begin select=2;found=1;end else if(eligible[0])begin select=0;found=1;end
   default:if(eligible[2])begin select=2;found=1;end else if(eligible[0])begin select=0;found=1;end else if(eligible[1])begin select=1;found=1;end
  endcase
 end
end
reg[255:0] selected_control;reg[1:0] selected_port,selected_count,selected_poison;reg[511:0] selected_data;
always @* begin
 selected_control=256'd0;selected_port=2'd0;selected_count=2'd0;selected_data=512'd0;selected_poison=2'd0;
 case(select)
  2'd0:begin selected_control=i_control[255:0];selected_port=i_port[1:0];selected_count=i_data_count[1:0];selected_data=i_data[511:0];selected_poison=i_data_poison[1:0];end
  2'd1:begin selected_control=i_control[511:256];selected_port=i_port[3:2];selected_count=i_data_count[3:2];selected_data=i_data[1023:512];selected_poison=i_data_poison[3:2];end
  default:begin selected_control=i_control[767:512];selected_port=i_port[5:4];selected_count=i_data_count[5:4];selected_data=i_data[1535:1024];selected_poison=i_data_poison[5:4];end
 endcase
end
wire active=i_rstn&&i_enable&&!error_q&&found;
wire source_fire=active&&i_valid[select]&&i_source_captured;
wire feedback_legal=i_data_accepted<=selected_count;
wire[1:0] taken=(active&&feedback_legal)?i_data_accepted:2'd0;
wire done=active&&(header_q||source_fire)&&(selected_count==taken);
assign o_valid=active&&i_valid[select];assign o_control=o_valid?selected_control:256'd0;assign o_port=active?selected_port:2'd0;
assign o_data_count=active?selected_count:2'd0;assign o_data=active?selected_data:512'd0;assign o_data_poison=active?selected_poison:2'd0;
assign o_owner_class=active?select:2'd0;assign o_busy=i_rstn&&(locked_q||(|i_valid));assign o_quiescent=i_rstn&&!locked_q&&!(|i_valid)&&!error_q;assign o_error=i_rstn&&error_q;
always @* begin
 o_source_captured=3'd0;o_data_accepted=6'd0;
 if(source_fire)o_source_captured[select]=1'b1;
 if(active)case(select)
  2'd0:o_data_accepted[1:0]=taken;
  2'd1:o_data_accepted[3:2]=taken;
  default:o_data_accepted[5:4]=taken;
 endcase
end
always @(posedge i_clk)begin
 if(!i_rstn)begin locked_q<=0;header_q<=0;error_q<=0;owner_q<=0;next_q<=0;end
 else begin
  if(malformed_offer||(i_source_captured&&!o_valid)||!feedback_legal)error_q<=1;
  if(!locked_q&&found&&!done)begin locked_q<=1;owner_q<=select;header_q<=source_fire;end
  else if(locked_q)begin
   if(source_fire)header_q<=1;
   if(done)begin locked_q<=0;header_q<=0;next_q<=(select==2)?0:select+1'b1;end
  end else if(done)begin next_q<=(select==2)?0:select+1'b1;header_q<=0;end
 end
end
endmodule
`default_nettype wire
