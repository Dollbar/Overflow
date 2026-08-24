# Apache-2.0. Run through run_sta_kd28.py; KD28_SRAM_LIBERTY selects the synthetic scenario.
read_liberty $::env(KD28_SRAM_LIBERTY)
read_verilog Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v
read_verilog technology/kd28/smoke/npu_kd28_sram_sta_top.v
link_design npu_kd28_sram_sta_top
read_sdc technology/kd28/constraints/npu_kd28_sram_sta_smoke.sdc
check_setup -verbose
puts "NPU_KD28_SRAM_STA_MAX_CHECK"
report_checks -path_delay max -group_path_count 20 -digits 3
report_worst_slack -max -digits 3
puts "NPU_KD28_SRAM_STA_MIN_CHECK"
report_checks -path_delay min -group_path_count 20 -digits 3
report_worst_slack -min -digits 3
