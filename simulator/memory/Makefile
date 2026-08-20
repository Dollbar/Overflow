.PHONY: help test functional rtl clean

PYTHON ?= python3

help:
	@echo "HBM model targets:"
	@echo "  make test       - run Python and RTL HBM model regressions"
	@echo "  make functional - run the Python HBM model regression"
	@echo "  make rtl        - run the SystemVerilog HBM beat-BFM regression"
	@echo "  make clean - remove generated HBM test output"

test: functional rtl

functional:
	$(PYTHON) scripts/run.py

rtl:
	$(PYTHON) scripts/run_rtl.py

clean:
	rm -rf work
