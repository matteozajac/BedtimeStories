#!/usr/bin/env python3
"""Audit every Mach-O in a local app, including dynamically linked Pulse frameworks."""

import argparse
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    magic = {bytes.fromhex(value) for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )}
    binaries = []
    symbols = []
    for path in sorted(args.app.rglob("*")):
        if not path.is_file():
            continue
        with path.open("rb") as file:
            if file.read(4) not in magic:
                continue
        binaries.append(str(path.relative_to(args.app)))
        symbols.append(subprocess.run(["nm", "-a", str(path)], check=True,
                                      capture_output=True, text=True).stdout)
    text = "\n".join(symbols + [str(path.relative_to(args.app)) for path in args.app.rglob("*")])
    # Match SDK identities, not the app-owned configureFirebase initializer label.
    forbidden = sorted(set(re.findall(
        r"RevenueCat|Sentry|Firebase(?:Core|Analytics|Auth|AppCheck|Firestore|Functions|Storage|Installations|SharedSwift)"
        r"|GoogleAppMeasurement|GoogleUtilities|FIR[A-Z][A-Za-z0-9_]*|APMAnalytics", text)))
    pulse = bool(re.search(r"Pulse(?:UI)?", "\n".join(symbols)))
    result = {"app": str(args.app), "binaries": binaries,
              "forbidden_local_sdk_matches": forbidden, "pulse_symbols_present": pulse,
              "passed": bool(binaries) and pulse and not forbidden}
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
