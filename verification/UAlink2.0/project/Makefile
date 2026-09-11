# Run from any directory with make -f /path/to/UALink/Makefile <target>.
# Outputs stay under build/ and reports/; tool commands may be overridden.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys
STA ?= sta
LIB_ROOT ?=
ROLE ?= 0
CORNER ?= ssg0p81v125c
PERIOD_NS ?= 0.640
WAIT ?= 0
HALF_PERIOD_PS ?= 320
RUN_DIR := $(ROOT_DIR)/build/connection_$(WAIT)_$(HALF_PERIOD_PS)
SYNTH_DIR := $(ROOT_DIR)/build/connection_synth_$(ROLE)_$(WAIT)
CELL_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib

.PHONY: model sim-connection synth-connection sta-connection hold-connection equiv-connection sta-hold-connection connection-check
model:
	cd "$(ROOT_DIR)" && $(PYTHON) -m unittest discover -s verification/model -p 'test_*.py' -v

sim-connection:
	@test "$(WAIT)" = 0 -o "$(WAIT)" = 1
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(RUN_DIR)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/connection_vectors.py" --wait "$(WAIT)" > "$(RUN_DIR)/vectors.mem"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_connection_tb --Mdir "$(RUN_DIR)/obj" -GC_WAIT=$(WAIT) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "$(ROOT_DIR)/rtl/upli/upli_connection_side.v" "$(ROOT_DIR)/verification/rtl/upli_connection_tb.v" > "$(RUN_DIR)/compile.log" 2>&1 || { tail -n 40 "$(RUN_DIR)/compile.log"; exit 1; }
	"$(RUN_DIR)/obj/Vupli_connection_tb" +VECTORS="$(RUN_DIR)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/connection_$(WAIT)_$(HALF_PERIOD_PS).log"

synth-connection:
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)"
	mkdir -p "$(SYNTH_DIR)" "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_BUILD_DIR="$(SYNTH_DIR)" UALINK_ROLE=$(ROLE) UALINK_WAIT=$(WAIT) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_connection.tcl" > "$(ROOT_DIR)/reports/connection_synth_$(ROLE)_$(WAIT).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/connection_synth_$(ROLE)_$(WAIT).log"; exit 1; }

sta-connection:
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(SYNTH_DIR)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_NETLIST="$(SYNTH_DIR)/mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_connection.tcl" > "$(ROOT_DIR)/reports/connection_sta_$(ROLE)_$(WAIT)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/connection_sta_$(ROLE)_$(WAIT)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }

hold-connection:
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(SYNTH_DIR)/mapped.json"
	$(PYTHON) "$(ROOT_DIR)/scripts/buffer_reset_guard.py" --input "$(SYNTH_DIR)/mapped.json" > "$(SYNTH_DIR)/hold_mapped.json"
	UALINK_JSON="$(SYNTH_DIR)/hold_mapped.json" UALINK_LIBERTY="$(CELL_LIB)" UALINK_BUILD_DIR="$(SYNTH_DIR)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/emit_connection_netlist.tcl" > "$(ROOT_DIR)/reports/connection_hold_$(ROLE)_$(WAIT).log" 2>&1 || { tail -n 40 "$(ROOT_DIR)/reports/connection_hold_$(ROLE)_$(WAIT).log"; exit 1; }

equiv-connection:
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(SYNTH_DIR)/hold_mapped.v"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_NETLIST="$(SYNTH_DIR)/hold_mapped.v" UALINK_ROLE=$(ROLE) UALINK_WAIT=$(WAIT) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_connection.tcl" > "$(ROOT_DIR)/reports/connection_equiv_$(ROLE)_$(WAIT).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/connection_equiv_$(ROLE)_$(WAIT).log"; exit 1; }

sta-hold-connection:
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(SYNTH_DIR)/hold_mapped.v"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_NETLIST="$(SYNTH_DIR)/hold_mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_connection.tcl" > "$(ROOT_DIR)/reports/connection_sta_hold_$(ROLE)_$(WAIT)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/connection_sta_hold_$(ROLE)_$(WAIT)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }

# Fresh, ordered implementation check. Separate recursive recipes remain ordered
# even with make -j. Mapping always uses the declared SSG synthesis corner; only
# the last stage uses the requested analysis corner. CLI overrides are inherited.
connection-check:
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/Makefile" synth-connection CORNER=ssg0p81v125c
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/Makefile" hold-connection CORNER=ssg0p81v125c
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/Makefile" equiv-connection CORNER=ssg0p81v125c
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/Makefile" sta-hold-connection

.DEFAULT_GOAL := help
.PHONY: help test rtl-smoke sram-smoke clean clean-dry-run
help:
	@echo "test | rtl-smoke | sram-smoke | prepared-tx-smoke KD28_ROOT=/authorized/path | native-endpoint-smoke KD28_ROOT=/authorized/path IP_RUN_LABEL=fresh | switch-egress-smoke IP_RUN_LABEL=fresh | ras-isolation-smoke IP_RUN_LABEL=fresh | ip-structure IP_RUN_LABEL=fresh | ip-module-smoke IP_RUN_LABEL=fresh | ip-top-smoke KD28_ROOT=/authorized/path IP_RUN_LABEL=fresh | clean-dry-run | clean"
test: model
	mkdir -p "$(ROOT_DIR)/build"
	cd "$(ROOT_DIR)" && $(PYTHON) -m unittest discover -s verification/tools -p 'test_*.py' -q
	$(PYTHON) "$(ROOT_DIR)/verification/tl_publish/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_receive/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_receive_credit/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_credit_admission/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_packer/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_channels/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_buffered/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_control_partition/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_prepared_partition/test_model.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_prepared_partition/test_mapped_state.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_prepared_partition/test_cost_relation.py"
rtl-smoke:
	$(PYTHON) "$(ROOT_DIR)/verification/tl_publish/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_publish/run_receiver.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_port/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_peers/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/rs/run_case.py" --serial 200 --lanes 1 --blocks 8 --label smoke
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_packer/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_channels/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_control_partition/run_rtl.py"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_prepared_partition/run_rtl.py" --label smoke
sram-smoke:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/tl_receive/run_rtl.py" --kd28-root "$(KD28_ROOT)"
	$(PYTHON) "$(ROOT_DIR)/verification/dl_replay/run_peers.py" --depth 3 --width 32 --group-size 2 --delay 3 --count 1100 --seed 17 --inject --dependency-root "$(KD28_ROOT)" --record smoke.json
	$(PYTHON) "$(ROOT_DIR)/verification/dl_replay/check_trace.py" --record smoke.json
	$(PYTHON) "$(ROOT_DIR)/verification/tl_receive_credit/run_rtl.py" --kd28-root "$(KD28_ROOT)"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_receive_credit/run_handoff.py" --kd28-root "$(KD28_ROOT)"
clean:
	$(PYTHON) "$(ROOT_DIR)/scripts/clean.py"
clean-dry-run:
	$(PYTHON) "$(ROOT_DIR)/scripts/clean.py" --dry-run

# Actual transmit SRAM queues; external library must be explicitly supplied.
.PHONY: tx-sram-smoke
tx-sram-smoke:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_buffered/run_fifo.py" --kd28-root "$(KD28_ROOT)"
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_buffered/run_peers.py" --kd28-root "$(KD28_ROOT)" --single --label smoke

# Complete source-group capture into production transmit SRAM queues.
.PHONY: prepared-tx-smoke
prepared-tx-smoke:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_prepared/run_unit.py" --kd28-root "$(KD28_ROOT)" --label smoke
	$(PYTHON) "$(ROOT_DIR)/verification/tl_control_partition/run_peers.py" --integrated --kd28-root "$(KD28_ROOT)" --single --label prepared_top_smoke
	$(PYTHON) "$(ROOT_DIR)/verification/tl_tx_prepared/check_capture.py" --labels prepared_top_smoke

# Two actual TL/DL peers with replay, receive SRAM and returned credit.
# Run: make endpoint-link-regression KD28_ROOT=/authorized/path RUN_LABEL=fresh
# Output: build/verification/endpoint_link/$(RUN_LABEL)/summary.json and cases.
# Next: review docs/endpoint_link_integration_review.md for transaction boundaries.
RUN_LABEL ?= endpoint_link
.PHONY: endpoint-link-regression
endpoint-link-regression:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/endpoint_link/run_matrix.py" --kd28-root "$(KD28_ROOT)" --label "$(RUN_LABEL)"

# Development Endpoint/Switch structure and actual digital top integration.
IP_RUN_LABEL ?= ip_tops
.PHONY: ip-structure ip-module-smoke ip-top-smoke ip-top-elaborate ip-top-synth
ip-structure:
	$(PYTHON) "$(ROOT_DIR)/scripts/check_ip_structure.py" --label "$(IP_RUN_LABEL)"
ip-module-smoke:
	$(PYTHON) "$(ROOT_DIR)/verification/endpoint_transaction/run_fields.py" --label "$(IP_RUN_LABEL)_fields" --faults
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_route_lookup.py" --label "$(IP_RUN_LABEL)_lookup"
ip-top-smoke: ip-structure
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch.py" --label "$(IP_RUN_LABEL)"
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_link.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)" --ports 4 --inject
ip-top-elaborate: ip-structure
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_elaboration.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)"
ip-top-synth: ip-structure
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_elaboration.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)" --synth

# Native Endpoint frontend and Switch physical-egress integration. Labels must
# be fresh because every runner keeps immutable source and result snapshots.
.PHONY: native-endpoint-smoke switch-egress-smoke ras-isolation-smoke
native-endpoint-smoke:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_endpoint_ip_top.py" --label "$(IP_RUN_LABEL)_native_top" --kd28-root "$(KD28_ROOT)" --static
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_response_collector.py" --label "$(IP_RUN_LABEL)_collector" --kd28-root "$(KD28_ROOT)" --faults --receive
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_rx_burst.py" --label "$(IP_RUN_LABEL)_burst" --kd28-root "$(KD28_ROOT)" --faults --receive
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_endpoint_burst_fault.py" --label "$(IP_RUN_LABEL)_burst_top" --kd28-root "$(KD28_ROOT)" --static
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_request_context.py" --label "$(IP_RUN_LABEL)_request_context" --integration --static
	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_endpoint_context_top.py" --label "$(IP_RUN_LABEL)_context_top" --kd28-root "$(KD28_ROOT)" --static
	$(PYTHON) "$(ROOT_DIR)/verification/endpoint_transaction/run_memory_adapter.py" --label "$(IP_RUN_LABEL)_memory_adapter" --faults --static

	$(PYTHON) "$(ROOT_DIR)/verification/upli_channels/run_endpoint_memory_top.py" --label "$(IP_RUN_LABEL)_memory_top" --kd28-root "$(KD28_ROOT)" --static

switch-egress-smoke:
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_scheduler.py" --label "$(IP_RUN_LABEL)_scheduler" --faults
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_pipeline.py" --label "$(IP_RUN_LABEL)_pipeline" --faults
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_repack.py" --label "$(IP_RUN_LABEL)_repack" --faults
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_typed_pipeline.py" --label "$(IP_RUN_LABEL)_typed_pipeline" --faults
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_typed_top.py" --label "$(IP_RUN_LABEL)_typed_top" --faults

	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_switch_egress_tl_context.py" --label "$(IP_RUN_LABEL)_tl_context" --faults

ras-isolation-smoke:
	$(PYTHON) -B "$(ROOT_DIR)/verification/ras/run_isolation.py" --label "$(IP_RUN_LABEL)_isolation" --faults

	$(PYTHON) -B "$(ROOT_DIR)/verification/ras/run_dummy.py" --label "$(IP_RUN_LABEL)_dummy" --faults

# Actual Read execution path through two Endpoint tops and the Switch.
.PHONY: ip-transaction-smoke ip-transaction-elaborate ip-transaction-capacity
ip-transaction-smoke:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/endpoint_transaction/run_transactions.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)" --inject
ip-transaction-elaborate: ip-structure
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/ip_tops/run_elaboration.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)" --transactions
ip-transaction-capacity:
	@test -n "$(KD28_ROOT)" || { echo "Set KD28_ROOT to the authorized external SRAM repository"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/verification/endpoint_transaction/run_capacity_matrix.py" --kd28-root "$(KD28_ROOT)" --label "$(IP_RUN_LABEL)"
