.PHONY: help test clean

PYTHON ?= python3

help:
	@echo "NPU NoC model targets:"
	@echo "  make test  - run deterministic Mesh model and unit regressions"
	@echo "  make clean - remove Python cache output"

test:
	$(PYTHON) scripts/run.py
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'

clean:
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
