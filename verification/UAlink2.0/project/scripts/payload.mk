# Run: make -f scripts/payload.mk sim-burst-payload PORTS=4 CREDIT_WIDTH=4
# Outputs: tagged vectors/oracle/compile/program under build and simulation report.
# Next: diagnostic faults, independent proof and actual integrated synthesis/STA.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := sim-burst-payload
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
VERILATOR ?= verilator
PORTS ?= 1
CREDIT_WIDTH ?= 4
REQUEST_WIDTH ?= 96
INIT_CYCLES ?= 2
HALF_PERIOD_PS ?= 320
TAG ?= initial
RUN_NAME := burst_payload_$(PORTS)_$(CREDIT_WIDTH)_$(REQUEST_WIDTH)_$(INIT_CYCLES)_$(HALF_PERIOD_PS)_$(TAG)
RUN_DIR := $(ROOT_DIR)/build/$(RUN_NAME)
SOURCES := $(ROOT_DIR)/rtl/upli/upli_credit_bank.v $(ROOT_DIR)/rtl/upli/upli_burst_control.v $(ROOT_DIR)/rtl/upli/upli_burst_sender.v

.PHONY: check-payload-config sim-burst-payload
check-payload-config:
	@case "$(TAG)" in ""|*[!A-Za-z0-9_]*) echo "Invalid payload run TAG" >&2; exit 1;; esac
	@test "$(PORTS)" = 1 -o "$(PORTS)" = 2 -o "$(PORTS)" = 4
	@test "$(CREDIT_WIDTH)" -ge 3 && test "$(CREDIT_WIDTH)" -le 16
	@test "$(REQUEST_WIDTH)" -ge 1 && test "$(REQUEST_WIDTH)" -le 1024
	@test "$(INIT_CYCLES)" -ge 2 && test "$(INIT_CYCLES)" -le 15
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200

sim-burst-payload: check-payload-config
	mkdir -p "$(RUN_DIR)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/burst_payload_vectors.py" --ports $(PORTS) --credit-width $(CREDIT_WIDTH) --request-width $(REQUEST_WIDTH) --init-cycles $(INIT_CYCLES) > "$(RUN_DIR)/vectors.mem" 2> "$(RUN_DIR)/oracle.log"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_burst_sender_tb --Mdir "$(RUN_DIR)/obj" -GC_NUM_PORTS=$(PORTS) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) -GC_REQUEST_WIDTH=$(REQUEST_WIDTH) -GC_INIT_CYCLES=$(INIT_CYCLES) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) $(SOURCES) "$(ROOT_DIR)/verification/rtl/upli_burst_sender_tb.v" > "$(RUN_DIR)/compile.log" 2>&1 || { tail -n 40 "$(RUN_DIR)/compile.log"; exit 1; }
	"$(RUN_DIR)/obj/Vupli_burst_sender_tb" +VECTORS="$(RUN_DIR)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/$(RUN_NAME).log"
