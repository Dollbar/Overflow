# HBM and SerDes Front-End Timing Abstractions

This directory provides scalar control-path Liberty cells for explicitly instantiated HBM and SerDes
digital boundaries. The three files are synthetic fast, typical, and slow scenarios. They let an open
front-end flow link black boxes and exercise setup, hold, and clock-to-output constraints before a target
device is selected.

The cells are `OVERFLOW_HBM_PORT_ABSTRACT` and `OVERFLOW_SERDES_SLICE_ABSTRACT`. Both carry
`dont_use : true`; synthesis must not infer or map logic into them. `REQ_DATA`, `RSP_DATA`, `TX_BLOCK`,
and `RX_BLOCK` are representative scalar timing pins. A real wrapper applies the same boundary constraint
to every vector bit or replaces the cell with the vendor macro view.

[`verilog/overflow_interface_blackboxes.v`](verilog/overflow_interface_blackboxes.v) provides matching
link shells. [`constraints/overflow_model_interfaces.sdc.template`](constraints/overflow_model_interfaces.sdc.template)
lists the required clock, I/O-delay, and multicycle categories; every angle-bracket token must be replaced
for the integration top before the file is passed to STA.

These libraries do not express the HBM transaction latency or the SerDes propagation/training latency.
Those are multi-cycle behavioral properties and belong in the integration SDC. The values in
[`profiles.yaml`](profiles.yaml) are repository-authored scenario scaling values, not silicon
characterization. They cannot support PVT, Fmax, power, area, analog, package, board, or signoff claims.

[`manifest.yaml`](manifest.yaml) records the package boundary, validation command, permitted claims, and
SHA-256 values for every controlled input. The regression rejects both checksum drift and disagreement
between `profiles.yaml` and the setup, hold, or clock-to-output arcs in any Liberty scenario.

Run `make sta-interfaces` from the repository root to parse and link each scenario with OpenSTA. The v0.1
qualification run passed fast, typical, and slow with constrained input, output, setup, hold, and
clock-to-output paths. Generated reports are under `technology/work/interface_sta/`.

For implementation, replace these files with controller/PHY/transceiver Liberty from the selected vendor
and record the process, PVT, checksum, license, generated clocks, I/O delays, and multicycle constraints in
`technology/vendor/library_set.local.yaml`.
