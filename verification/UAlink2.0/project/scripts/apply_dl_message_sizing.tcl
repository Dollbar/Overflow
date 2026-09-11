# Run inside Yosys with UALINK_SIZE_CHANGES, UALINK_NETLIST, UALINK_LIBERTY.
# Output: original graph with exactly checked cell-type substitutions only.
# Next: emit area/JSON/netlist, full mapped equivalence, every corner and clock.
foreach key {UALINK_SIZE_CHANGES UALINK_NETLIST UALINK_LIBERTY} {
    if {![info exists env($key)] || ![file isfile $env($key)]} {error "Missing $key"}
}
yosys design -reset
yosys read_liberty -lib -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
set journal_file [open $env(UALINK_SIZE_CHANGES) r]
set journal [read $journal_file]
close $journal_file
foreach change $journal {
    if {[llength $change] != 3} {error "Malformed DL message sizing journal entry"}
    lassign $change instance original replacement
    if {$instance eq "" || $original eq "" || $replacement eq ""} {error "Empty sizing field"}
    # Check the instance selection itself, not just its old-type intersection:
    # otherwise a wildcard may silently resize additional cells of other types.
    yosys select -assert-count 1 dl_message_arbiter/c:$instance
    yosys select -assert-count 1 dl_message_arbiter/c:$instance dl_message_arbiter/t:$original %i
    yosys chtype -set $replacement dl_message_arbiter/c:$instance
}
yosys select *
