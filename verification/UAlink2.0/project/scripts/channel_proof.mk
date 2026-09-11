# Run: make -f scripts/channel_proof.mk prove-channel KD28_ROOT=/path/to/authorized/repository
# Outputs: reports/channel_ownership_TAG.log, build/channel_proof_TAG/{instrumented.v,properties.json}.
# Next: inspect counterexamples/mutations and actual-memory metadata tests; not full-IP signoff.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := prove-channel
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
YOSYS ?= yosys
KD28_ROOT ?=
PORTS ?= 1
WIDTH ?= 8
CREDIT_WIDTH ?= 4
CAP_HEX ?= 50132
RETURN_DEPTH ?= 4
TAG ?= $(PORTS)_$(WIDTH)_$(CREDIT_WIDTH)_$(CAP_HEX)_$(RETURN_DEPTH)
PROOF_RUN := $(ROOT_DIR)/build/channel_proof_$(TAG)
PROOF_LOG := $(ROOT_DIR)/reports/channel_ownership_$(TAG).log
.PHONY: prove-channel
prove-channel:
	@test -n "$(KD28_ROOT)"
	mkdir -p "$(ROOT_DIR)/reports" "$(PROOF_RUN)"
	UALINK_PORTS=$(PORTS) UALINK_WIDTH=$(WIDTH) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_CAP_HEX=$(CAP_HEX) UALINK_RETURN_DEPTH=$(RETURN_DEPTH) UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_BUILD_DIR="$(PROOF_RUN)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_channel.tcl" > "$(PROOF_LOG)" 2>&1 || { tail -n 35 "$(PROOF_LOG)"; exit 1; }
