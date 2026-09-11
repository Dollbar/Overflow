# Run from Yosys with UALINK_SIZE_CHANGES, UALINK_NETLIST and UALINK_LIBERTY.
# Output: reload the original serialized graph and change only cell types.
# Next: check -assert, emit mapped artifacts, independent equivalence and STA.
foreach key {UALINK_SIZE_CHANGES UALINK_NETLIST UALINK_LIBERTY} {
    if {![info exists env($key)] || ![file isfile $env($key)]} {error "Missing $key"}
}
# Yosys may rename auto-generated cells on export. Reload the exact pre-sizing
# file supplied to OpenSTA, not its constant-dropping export or pre-export names.
yosys design -reset
yosys read_liberty -lib -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
set journal_file [open $env(UALINK_SIZE_CHANGES) r]
set journal [read $journal_file]
close $journal_file
foreach change $journal {
    if {[llength $change] != 3} {error "Malformed burst sizing journal entry"}
    lassign $change instance original replacement
    if {$instance eq "" || $original eq "" || $replacement eq ""} {error "Empty sizing field"}
    # Intersect the exact target selection and old type before applying a step.
    # A stale journal, missing cell or ambiguous selector cannot silently succeed.
    yosys select -assert-count 1 upli_burst_control/c:$instance upli_burst_control/t:$original %i
    yosys chtype -set $replacement upli_burst_control/c:$instance
}
yosys select *
