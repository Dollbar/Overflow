#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Parse, link, constrain, and report every abstract HBM/SerDes Liberty scenario.

Command: ``python3 technology/scripts/run_sta_interfaces.py`` or ``make sta-interfaces``.
Outputs: ``technology/work/interface_sta/opensta_{fast,typical,slow}.log``.
Next: replace synthetic views with licensed macro Liberty for physical implementation.
"""

from __future__ import annotations

from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "technology" / "work" / "interface_sta"
SCRIPT = ROOT / "technology" / "scripts" / "sta_interface_smoke.tcl"
LIBRARIES = {
    corner: ROOT / "Library" / "timing" / "interfaces" / f"overflow_hbm_serdes_abstract_{corner}.lib"
    for corner in ("fast", "typical", "slow")
}


def main() -> int:
    opensta = shutil.which("sta") or shutil.which("opensta")
    if not opensta:
        raise SystemExit("required tool was not found in PATH: sta or opensta")
    WORK.mkdir(parents=True, exist_ok=True)
    local_lib = str(Path(opensta).resolve().parent.parent / "lib")
    for corner, liberty in LIBRARIES.items():
        environment = os.environ.copy()
        environment["OVERFLOW_INTERFACE_LIBERTY"] = str(liberty)
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
        required_markers = ("OVERFLOW_STA_MAX_CHECK", "OVERFLOW_STA_MIN_CHECK")
        if any(marker not in result.stdout for marker in required_markers):
            raise SystemExit(f"OpenSTA omitted max/min checks for {corner}; inspect {log.relative_to(ROOT)}")
        if result.stdout.count("slack (MET)") < 2:
            raise SystemExit(f"OpenSTA did not report met max/min timing for {corner}; inspect {log.relative_to(ROOT)}")
        print(f"[STA_INTERFACE PASS] {corner} report={log.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
