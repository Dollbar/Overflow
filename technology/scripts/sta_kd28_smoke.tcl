# Apache-2.0. Run through run_sta_kd28.py; KD28_SRAM_LIBERTY selects the synthetic scenario.
read_liberty $::env(KD28_SRAM_LIBERTY)
read_verilog Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v
read_verilog technology/kd28/smoke/kd28_sta_smoke_top.v
link_design kd28_sta_smoke_top
read_sdc technology/kd28/constraints/kd28_sta_smoke.sdc
check_setup -verbose
puts "KD28_STA_MAX_CHECK"
report_checks -path_delay max -group_path_count 20 -digits 3
report_worst_slack -max -digits 3
puts "KD28_STA_MIN_CHECK"
report_checks -path_delay min -group_path_count 20 -digits 3
report_worst_slack -min -digits 3
