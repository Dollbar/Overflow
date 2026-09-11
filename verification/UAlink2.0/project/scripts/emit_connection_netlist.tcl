# Run after buffer_reset_guard.py with UALINK_JSON, UALINK_LIBERTY, UALINK_BUILD_DIR.
# Outputs: hold_mapped.v and hold_area.json. Next: equivalence and unchanged STA.
foreach key {UALINK_JSON UALINK_LIBERTY UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
yosys read_json $env(UALINK_JSON)
yosys hierarchy -check -top upli_connection_side
yosys check -assert
yosys tee -o [file join $run_dir hold_area.json] stat -json -liberty $env(UALINK_LIBERTY)
yosys write_verilog -noattr -noexpr [file join $run_dir hold_mapped.v]
