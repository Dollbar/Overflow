// Public verification fixtures for the bounded single64B Read scenario.
// These functions describe local stimulus and test memory, not additional UALink encodings.
package ualink_test_pkg;
 localparam integer TEST_TRANSACTION_COUNT=8;
 localparam integer TEST_MEMORY_BYTES=4096;

 function automatic logic [10:0] tag_at(input integer number);
  case(number)
   0:tag_at=11'd0;
   1:tag_at=11'd4;
   2:tag_at=11'd1024;
   3:tag_at=11'd2044;
   4:tag_at=11'd1;
   5:tag_at=11'd5;
   6:tag_at=11'd1025;
   default:tag_at=11'd2045;
  endcase
 endfunction

 function automatic logic [56:0] address_at(input integer number);
  address_at=(number==7)?57'h100000000000000:number*64;
 endfunction

 function automatic integer tag_index(input logic [10:0] value);
  tag_index=-1;
  for(integer index=0;index<TEST_TRANSACTION_COUNT;index=index+1)
   if(value==tag_at(index))tag_index=index;
 endfunction

 function automatic integer address_index(input logic [56:0] value);
  address_index=-1;
  for(integer index=0;index<TEST_TRANSACTION_COUNT;index=index+1)
   if(value==address_at(index))address_index=index;
 endfunction

 // BFM data generation only. Completion scoreboards must use their own frozen expectations.
 function automatic logic [511:0] memory_word(input integer side,input logic [56:0] address);
  memory_word=512'd0;
  if(address<TEST_MEMORY_BYTES)
   for(integer byte_lane=0;byte_lane<64;byte_lane=byte_lane+1)
    memory_word[byte_lane*8+:8]=(side*61+(address>>6)*29+byte_lane*17+(byte_lane^(address>>6)))&255;
 endfunction
endpackage
