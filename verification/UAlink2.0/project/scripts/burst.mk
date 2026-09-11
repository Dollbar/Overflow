# Run: make -f scripts/burst.mk sim-burst-control PORTS=4 CREDIT_WIDTH=4
# Outputs: tagged build/burst_control_* vectors/programs and reports/burst_control_* logs.
# Next: prove-burst-control, then burst-check with explicit authorized LIB_ROOT.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := sim-burst-control
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys
ABC ?= yosys-abc
STA ?= sta
LIB_ROOT ?=
MAPPING_CORNER ?= ssg0p81vm40c
CORNER ?= ssg0p81vm40c
PERIOD_NS ?= 0.640
PORTS ?= 1
CREDIT_WIDTH ?= 4
HALF_PERIOD_PS ?= 320
TAG ?= timing
RUN_DIR := $(ROOT_DIR)/build/burst_control_$(PORTS)_$(CREDIT_WIDTH)_$(HALF_PERIOD_PS)_$(TAG)
SYNTH_DIR := $(ROOT_DIR)/build/burst_control_synth_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(TAG)
CELL_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib
MAPPING_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(MAPPING_CORNER).lib
REPORT_PREFIX := $(ROOT_DIR)/reports/burst_control
IDENTITY_ENV = UALINK_BUILD_DIR="$(SYNTH_DIR)" UALINK_MAPPING_LIBERTY="$(MAPPING_LIB)" UALINK_YOSYS="$(YOSYS)" UALINK_ABC="$(ABC)" UALINK_STA="$(STA)" UALINK_PORTS=$(PORTS) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_MAPPING_CORNER=$(MAPPING_CORNER)
MAPPED_ENV = $(IDENTITY_ENV) UALINK_NETLIST="$(SYNTH_DIR)/mapped.v"

.PHONY: check-burst-config sim-burst-control prove-burst-control
check-burst-config:
	@case "$(TAG)" in ""|*[!A-Za-z0-9_]*) echo "Invalid burst run TAG" >&2; exit 1;; esac
	@test "$(PORTS)" = 1 -o "$(PORTS)" = 2 -o "$(PORTS)" = 4
	@test "$(CREDIT_WIDTH)" -ge 3 && test "$(CREDIT_WIDTH)" -le 16
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	@case "$(MAPPING_CORNER)" in ssg0p81v125c|ssg0p81vm40c) ;; *) echo "Undeclared mapping corner" >&2; exit 1;; esac
	@case "$(CORNER)" in tt0p9v25c|ssg0p81v125c|ssg0p81vm40c|ffg0p99v125c|ffg0p99vm40c) ;; *) echo "Undeclared analysis corner" >&2; exit 1;; esac
	@test "$(PERIOD_NS)" = 0.640 -o "$(PERIOD_NS)" = 6.400

sim-burst-control: check-burst-config
	mkdir -p "$(RUN_DIR)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/burst_control_vectors.py" --ports $(PORTS) --credit-width $(CREDIT_WIDTH) > "$(RUN_DIR)/vectors.mem" 2> "$(RUN_DIR)/oracle.log"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_burst_control_tb --Mdir "$(RUN_DIR)/obj" -GC_NUM_PORTS=$(PORTS) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "$(ROOT_DIR)/rtl/upli/upli_burst_control.v" "$(ROOT_DIR)/verification/rtl/upli_burst_control_tb.v" > "$(RUN_DIR)/compile.log" 2>&1 || { tail -n 40 "$(RUN_DIR)/compile.log"; exit 1; }
	"$(RUN_DIR)/obj/Vupli_burst_control_tb" +VECTORS="$(RUN_DIR)/vectors.mem" 2>&1 | tee "$(REPORT_PREFIX)_$(PORTS)_$(CREDIT_WIDTH)_$(HALF_PERIOD_PS)_$(TAG).log"

prove-burst-control: check-burst-config
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_PORTS=$(PORTS) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_burst_control.tcl" > "$(REPORT_PREFIX)_proof_$(PORTS)_$(CREDIT_WIDTH)_$(TAG).log" 2>&1 || { tail -n 25 "$(REPORT_PREFIX)_proof_$(PORTS)_$(CREDIT_WIDTH)_$(TAG).log"; exit 1; }

# Run: make -f scripts/burst.mk burst-check LIB_ROOT=/path/to/authorized/libs PORTS=4.
# Outputs: actual mapped.v/mapped.json/area.json plus build_identity.json and separate logs.
# Next: repeat analysis CORNER and PERIOD_NS on the identical guarded mapped netlist.
.PHONY: synth-burst-control equiv-burst-control sta-burst-control burst-check
synth-burst-control: check-burst-config
	@test -n "$(LIB_ROOT)" && test -f "$(MAPPING_LIB)"
	mkdir -p "$(ROOT_DIR)/reports"
	$(IDENTITY_ENV) UALINK_LIBERTY="$(MAPPING_LIB)" $(PYTHON) "$(ROOT_DIR)/scripts/burst_build_identity.py" synth -- $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_burst_control.tcl" > "$(REPORT_PREFIX)_synth_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(TAG).log" 2>&1 || { tail -n 30 "$(REPORT_PREFIX)_synth_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(TAG).log"; exit 1; }

equiv-burst-control: check-burst-config
	@test -n "$(LIB_ROOT)" && test -f "$(MAPPING_LIB)"
	mkdir -p "$(ROOT_DIR)/reports"
	$(MAPPED_ENV) UALINK_LIBERTY="$(MAPPING_LIB)" $(PYTHON) "$(ROOT_DIR)/scripts/burst_build_identity.py" equiv -- $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_burst_control.tcl" > "$(REPORT_PREFIX)_equiv_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(TAG).log" 2>&1 || { tail -n 30 "$(REPORT_PREFIX)_equiv_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(TAG).log"; exit 1; }

sta-burst-control: check-burst-config
	@test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(MAPPING_LIB)"
	mkdir -p "$(ROOT_DIR)/reports"
	$(MAPPED_ENV) UALINK_LIBERTY="$(CELL_LIB)" UALINK_PERIOD_NS=$(PERIOD_NS) $(PYTHON) "$(ROOT_DIR)/scripts/burst_build_identity.py" sta -- $(STA) -exit "$(ROOT_DIR)/scripts/sta_burst_control.tcl" > "$(REPORT_PREFIX)_sta_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(CORNER)_$(PERIOD_NS)_$(TAG).log" 2>&1 || { tail -n 15 "$(REPORT_PREFIX)_sta_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(CORNER)_$(PERIOD_NS)_$(TAG).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_sta_report.py" "$(REPORT_PREFIX)_sta_$(PORTS)_$(CREDIT_WIDTH)_$(MAPPING_CORNER)_$(CORNER)_$(PERIOD_NS)_$(TAG).log" --design burst_control

# Recursive stages remain ordered even if the caller requests make -j.
burst-check:
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/burst.mk" synth-burst-control
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/burst.mk" equiv-burst-control
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/burst.mk" sta-burst-control
