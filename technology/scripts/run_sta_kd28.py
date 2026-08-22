#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Parse, link, constrain, and report every synthetic KD28 SRAM scenario.

Command: ``python3 technology/scripts/run_sta_kd28.py`` or ``make sta-kd28``.
Outputs: ``technology/work/kd28_sta/opensta_{fast,typical,slow}.log``.
Next: replace synthetic views with licensed macro Liberty for physical implementation.
"""

from __future__ import annotations

from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "technology" / "work" / "kd28_sta"
SCRIPT = ROOT / "technology" / "scripts" / "sta_kd28_smoke.tcl"
LIBRARIES = {
    corner: ROOT / "Library" / "timing" / "kd28" / "sram" / f"kd28_sram_{corner}.lib"
    for corner in ("fast", "typical", "slow")
}


def main() -> int:
    """Run OpenSTA for every generated KD28 synthetic timing scenario."""
    opensta = shutil.which("sta") or shutil.which("opensta")
    if not opensta:
        raise SystemExit("required tool was not found in PATH: sta or opensta")
    WORK.mkdir(parents=True, exist_ok=True)
    local_lib = str(Path(opensta).resolve().parent.parent / "lib")
    for corner, liberty in LIBRARIES.items():
        environment = os.environ.copy()
        environment["KD28_SRAM_LIBERTY"] = str(liberty)
        environment["LD_LIBRARY_PATH"] = local_lib + os.pathsep + environment.get("LD_LIBRARY_PATH", "")
        result = subprocess.run(
            [opensta, "-exit", str(SCRIPT)],
            cwd=ROOT,
            env=environment,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        log = WORK / f"opensta_{corner}.log"
        log.write_text(result.stdout, encoding="ascii")
        if result.returncode:
            raise SystemExit(f"OpenSTA failed for {corner}; inspect {log.relative_to(ROOT)}")
        if re.search(r"^(Error|Warning)", result.stdout, re.MULTILINE):
            raise SystemExit(f"OpenSTA reported diagnostics for {corner}; inspect {log.relative_to(ROOT)}")
        required = ("KD28_STA_MAX_CHECK", "KD28_STA_MIN_CHECK")
        if any(marker not in result.stdout for marker in required):
            raise SystemExit(f"OpenSTA omitted max/min checks for {corner}; inspect {log.relative_to(ROOT)}")
        if result.stdout.count("slack (MET)") < 2:
            raise SystemExit(f"OpenSTA did not report met max/min timing for {corner}; inspect {log.relative_to(ROOT)}")
        print(f"[STA_KD28 PASS] {corner} report={log.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
