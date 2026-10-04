#!/usr/bin/env python3
"""Capture and verify the opt-in operations UI on a disposable simulator."""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUNDLE = "com.matteozajac.bedtimestories"


def run(*arguments, allow_failure=False):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode and not allow_failure:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Disposable simulator UDID")
    parser.add_argument("--app", type=Path, help="An already built Internal or Debug app")
    parser.add_argument("--language", choices=("en", "pl"), default="en")
    parser.add_argument("--output", type=Path, default=REPO / "docs/qa")
    args = parser.parse_args()
    cli = shutil.which("rocketsim")
    if not cli:
        raise RuntimeError("The RocketSim CLI must be installed and RocketSim must be running.")
    args.output.mkdir(parents=True, exist_ok=True)
    if args.app:
        run("xcrun", "simctl", "install", args.simulator, str(args.app.resolve()))
    run(sys.executable, str(REPO / "scripts/seed-simulator.py"), args.simulator)
    run("xcrun", "simctl", "terminate", args.simulator, BUNDLE, allow_failure=True)
    container = Path(run("xcrun", "simctl", "get_app_container", args.simulator, BUNDLE, "data").strip())
    history_path = container / "Library/Application Support/Operations/operations.json"
    if history_path.exists():
        history = json.loads(history_path.read_text())
        # Recreate only opt-in fixtures so persisted captions use the chosen locale.
        history = [operation for operation in history
                   if operation["id"] not in ("qa-active-narration", "qa-ready-story")]
        temporary = history_path.with_suffix(".qa-tmp")
        temporary.write_text(json.dumps(history, ensure_ascii=False))
        temporary.replace(history_path)
    run("xcrun", "simctl", "launch", args.simulator, BUNDLE, "--qa-library", "--qa-operations",
        "--qa-operation-banner", "-AppleLanguages", f"({args.language})", "-AppleLocale",
        "pl_PL" if args.language == "pl" else "en_US")

    def rocket(*arguments):
        result = json.loads(run(cli, *arguments, "--udid", args.simulator))
        if not result.get("ok"):
            raise RuntimeError(json.dumps(result.get("error"), ensure_ascii=False))
        preview = result.get("context", {}).get("preview_url")
        if preview:
            print(f"Live preview: {preview}", flush=True)
        return result

    def capture(name):
        destination = args.output / f"operations-{name}-{args.language}.png"
        with destination.open("wb") as output:
            subprocess.run([cli, "screenshot", "--udid", args.simulator], stdout=output, check=True)
        print(destination, flush=True)

    banner = "Już gotowe" if args.language == "pl" else "Ready for you"
    status = "W toku: 1" if args.language == "pl" else "1 in progress"
    title = "Zadania w toku" if args.language == "pl" else "Ongoing Operations"
    open_book = "Otwórz książkę" if args.language == "pl" else "Open Book"
    rocket("wait", "element", "--label", banner, "--type", "button", "--timeout", "20")
    capture("banner")

    history = json.loads(history_path.read_text())
    active = next(operation for operation in history if operation["id"] == "qa-active-narration")
    book_title = active["title"]
    book_id = active["destination"]["book"]["_0"]
    rocket("interact", "tap", "--label", banner, "--type", "button", "--screen", "latest")
    rocket("wait", "element", "--label", book_title, "--type", "heading", "--timeout", "5")
    capture("banner-destination")
    rocket("interact", "tap", "--label", status, "--type", "button", "--screen", "latest")
    rocket("wait", "element", "--label", title, "--type", "heading", "--timeout", "5")
    capture("list")
    rocket("interact", "tap", "--label", open_book, "--type", "button", "--index", "1", "--screen", "latest")
    rocket("wait", "element", "--label", book_title, "--type", "heading", "--timeout", "5")
    capture("list-destination")
    run("xcrun", "simctl", "openurl", args.simulator, "bedtimestories://operation/qa-ready-story")
    confirmation = rocket("elements", "--agent", "--agent-mode", "nav")
    for row in confirmation.get("data", {}).get("rows", []):
        parts = row.split("|")
        if len(parts) >= 3 and parts[1] == "button" and parts[2] in ("Open", "Otwórz"):
            rocket("interact", "tap", "--label", parts[2], "--type", "button", "--screen", "latest")
            break
    rocket("wait", "element", "--label", book_title, "--type", "heading", "--timeout", "5")
    library_menu = "Opcje biblioteki" if args.language == "pl" else "Library actions"
    settings_title = "Ustawienia" if args.language == "pl" else "Settings"
    rocket("interact", "tap", "--label", library_menu, "--type", "popUpButton", "--screen", "latest")
    rocket("interact", "tap", "--label", settings_title, "--type", "button", "--screen", "latest")
    rocket("wait", "element", "--label", settings_title, "--type", "heading", "--timeout", "5")
    capture("settings")
    rocket("interact", "tap", "--label", title, "--type", "button", "--screen", "latest")
    rocket("wait", "element", "--label", title, "--type", "heading", "--timeout", "5")
    snapshot = rocket("elements", "--agent", "--agent-mode", "nav")
    evidence = {
        "simulator": args.simulator,
        "language": args.language,
        "bookID": book_id,
        "bookTitle": book_title,
        "checks": ["completion_banner", "ongoing_operations", "banner_book_navigation", "list_book_navigation", "operation_url", "settings_operations_link"],
        "snapshot": {"rs": snapshot.get("rs"), "ok": snapshot.get("ok"), "data": snapshot.get("data")},
        "scope": "Seeded simulator UI; no remote notification or physical-device claim.",
    }
    (args.output / f"operations-evidence-{args.language}.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(f"Verified operation destinations for book {book_id}: {book_title}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
