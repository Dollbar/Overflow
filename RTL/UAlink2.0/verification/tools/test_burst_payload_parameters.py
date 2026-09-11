"""Actual Yosys hierarchy checks for staged sender parameter boundaries.

Run: python3 -m unittest discover -s verification/tools -p test_burst_payload_parameters.py -v
Outputs: retained command/log/summary fixtures in build/payload_parameters_*.
Next: behavioral capacity profiles and mapped implementation; elaboration is
neither equivalence nor timing. Missing Yosys is a failure, not a passing skip.
"""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PayloadParameterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[2]
        cls.yosys = shutil.which("yosys")
        if cls.yosys is None:
            raise RuntimeError("Yosys is required for actual hierarchy validation")
        cls.sources = [cls.root/"rtl/upli"/name for name in
                       ("upli_credit_bank.v", "upli_burst_control.v", "upli_burst_sender.v")]
        cls.identity = {str(p.relative_to(cls.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in cls.sources}
        cls.fixture_root = Path(tempfile.mkdtemp(prefix="payload_parameters_", dir=cls.root/"build"))
        cls.results = []

    @classmethod
    def tearDownClass(cls):
        if cls.identity != {str(p.relative_to(cls.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in cls.sources}:
            raise AssertionError("RTL changed while hierarchy checks ran")
        (cls.fixture_root/"summary.json").write_text(json.dumps({"source_sha256": cls.identity,
            "scope": "hierarchy_elaboration_only", "cases": cls.results}, indent=2)+"\n")

    def elaborate(self, name, parameters):
        script = "read_verilog " + " ".join(json.dumps(str(p)) for p in self.sources)
        script += "; hierarchy -check -top upli_burst_sender "
        script += " ".join(f"-chparam {key} {value}" for key, value in parameters.items())
        script += "; check -assert"
        with (self.fixture_root/f"{name}.log").open("w") as output:
            result = subprocess.run([self.yosys, "-Q", "-T", "-p", script], cwd=self.root,
                                    stdout=output, stderr=subprocess.STDOUT, check=False, timeout=60)
        text = (self.fixture_root/f"{name}.log").read_text()
        self.results.append({"name": name, "parameters": parameters, "status": result.returncode,
                             "command": script, "log": f"{name}.log"})
        return result.returncode, text

    def test_valid_port_width_and_independent_capacity_parameters_elaborate(self):
        for port in (1, 2, 4):
            for width in (3, 4, 16):
                with self.subTest(ports=port, credit_width=width):
                    # Distinct, zero, and upper-bit capacities test actual parameter
                    # propagation/elaboration only; not credit behavior coverage.
                    capacity = (1 << width)-1
                    values = {"C_NUM_PORTS": port, "C_CREDIT_WIDTH": width,
                              "C_REQUEST_WIDTH": 1 if width == 3 else 129,
                              "C_REQ_CAPACITIES": f"{port*5*width}'h{capacity:x}",
                              "C_DATA_CAPACITIES": "0", "C_INIT_CYCLES": 15}
                    status, text = self.elaborate(f"valid_{port}_{width}", values)
                    self.assertEqual(status, 0, text[-2500:])
                    self.assertNotIn("ERROR:", text)

    def test_invalid_parameters_are_rejected_by_real_hierarchy_guards(self):
        for name, values in (
            ("port_three", {"C_NUM_PORTS": 3}),
            ("port_five", {"C_NUM_PORTS": 5}),
            ("credit_two", {"C_CREDIT_WIDTH": 2}),
            ("credit_seventeen", {"C_CREDIT_WIDTH": 17}),
            ("request_zero", {"C_REQUEST_WIDTH": 0}),
            ("init_one", {"C_INIT_CYCLES": 1}),
            ("init_counter_too_narrow", {"C_INIT_COUNT_WIDTH": 1, "C_INIT_CYCLES": 2}),
            ("init_counter_too_wide", {"C_INIT_COUNT_WIDTH": 17}),
        ):
            with self.subTest(name=name):
                status, text = self.elaborate(name, values)
                self.assertNotEqual(status, 0, "invalid parameters silently elaborated")
                self.assertRegex(text, r"ERROR: Module .*upli_.*invalid.*not part of the design")


if __name__ == "__main__":
    unittest.main()
