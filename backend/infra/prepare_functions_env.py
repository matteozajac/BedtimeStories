#!/usr/bin/env python3
"""Generate safe identifier-only Functions env from Terraform JSON outputs; feature stays off."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outputs-json", type=Path, required=True)
    parser.add_argument("--functions-dir", type=Path, default=Path(__file__).resolve().parents[1] / "functions")
    options = parser.parse_args()
    outputs = json.loads(options.outputs_json.read_text())
    environment = outputs["functions_environment"]["value"]
    expected = {"ENABLE_CLOUD_NARRATION", "PROJECT_ID", "API_SERVICE_ACCOUNT", "VOICE_BUCKET", "OUTPUT_BUCKET", "KMS_KEY_NAME",
                "TASK_LOCATION", "TASK_QUEUE", "TASK_SERVICE_ACCOUNT", "WORKER_URL"}
    if set(environment) != expected or environment.get("ENABLE_CLOUD_NARRATION") != "false":
        parser.error("The outputs must contain only safe configuration identifiers with the feature gate false.")
    project = environment["PROJECT_ID"]
    if project != "gen-lang-client-0154884984":
        parser.error("Unexpected project identity.")
    if environment["VOICE_BUCKET"] != project + "-voices" or environment["OUTPUT_BUCKET"] != project + "-audio" or environment["TASK_LOCATION"] != "europe-west1" or environment["TASK_QUEUE"] != "bedtime-voice-worker":
        parser.error("The bucket, region, and queue must belong to the exact environment.")
    if environment["API_SERVICE_ACCOUNT"] != f"voice-api@{project}.iam.gserviceaccount.com" or environment["TASK_SERVICE_ACCOUNT"] != f"voice-queue@{project}.iam.gserviceaccount.com":
        parser.error("Unexpected runtime identity.")
    if not environment["KMS_KEY_NAME"].startswith(f"projects/{project}/locations/europe-west1/keyRings/"):
        parser.error("Unexpected KMS project or region.")
    url = urlsplit(environment["WORKER_URL"])
    if url.scheme != "https" or not url.hostname or not url.hostname.endswith(".run.app") or url.path not in {"", "/"} or url.query or url.fragment or url.username or url.password:
        parser.error("Build and provision the private worker before generating its base-URL environment.")
    if any(not isinstance(value, str) or any(character in value for character in "\n\r\"'\\ ") for value in environment.values()):
        parser.error("Unsafe environment value.")
    target = options.functions_dir / f".env.{project}"
    target.write_text("".join(f"{key}={value}\n" for key, value in sorted(environment.items())))
    print(f"Wrote safe identifier configuration to {target}; cloud narration remains disabled.")


if __name__ == "__main__":
    main()
