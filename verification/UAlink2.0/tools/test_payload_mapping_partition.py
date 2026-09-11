"""A full four-port mapped sender must prove, without timeout or lost state."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PayloadMappingPartitionTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("UALINK_TEST_LIBERTY") and shutil.which("yosys"),
                         "explicit authorized UALINK_TEST_LIBERTY and Yosys required")
    def test_four_port_full_width_mapped_equivalence_closes(self):
        root = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
        with tempfile.TemporaryDirectory(prefix="ualink_four_port_mapping_") as directory:
            env = dict(os.environ, UALINK_LIBERTY=os.environ["UALINK_TEST_LIBERTY"],
                       UALINK_BUILD_DIR=directory, UALINK_PORTS="4", UALINK_CREDIT_WIDTH="16",
                       UALINK_REQUEST_WIDTH="96", UALINK_INIT_CYCLES="2")
            mapped = subprocess.run(["yosys", "-Q", "-T", "-c",
                str(root/"scripts/synth_burst_sender.tcl")], env=env, cwd=root.parent,
                text=True, capture_output=True, timeout=300, check=False)
            self.assertEqual(mapped.returncode, 0, mapped.stdout[-2000:]+mapped.stderr)
            env["UALINK_NETLIST"] = str(Path(directory)/"mapped.v")
            proof = subprocess.run(["yosys", "-Q", "-T", "-c",
                str(root/"scripts/equiv_burst_sender.tcl")], env=env, cwd=root.parent,
                text=True, capture_output=True, timeout=900, check=False)
            self.assertEqual(proof.returncode, 0, proof.stdout[-3000:]+proof.stderr)
            self.assertNotIn("proof did time out", proof.stdout)
            self.assertNotIn("Warning:", proof.stdout)


if __name__ == "__main__":
    unittest.main()
