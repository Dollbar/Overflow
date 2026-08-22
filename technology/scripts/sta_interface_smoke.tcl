# Apache-2.0. Run through run_sta_interfaces.py; OVERFLOW_INTERFACE_LIBERTY selects the scenario.
# OpenSTA writes fast/typical/slow logs under technology/work/interface_sta. After this portable smoke
# check, use a selected macro Liberty and integration SDC for any physical timing work.
read_liberty $::env(OVERFLOW_INTERFACE_LIBERTY)
read_verilog technology/interfaces/smoke/interface_smoke_top.v
link_design interface_smoke_top
read_sdc technology/interfaces/constraints/interface_smoke.sdc
check_setup -verbose
puts "OVERFLOW_STA_MAX_CHECK"
report_checks -path_delay max -group_path_count 10 -digits 3
report_worst_slack -max -digits 3
puts "OVERFLOW_STA_MIN_CHECK"
report_checks -path_delay min -group_path_count 10 -digits 3
report_worst_slack -min -digits 3
