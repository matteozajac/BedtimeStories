#!/usr/bin/env python3
"""Explicit Firebase Storage registration; ADC is consumed without printing credentials."""
import argparse
import json
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--register", action="store_true", help="Perform addFirebase after successful ownership verification.")
    parser.add_argument("--configure-cli", action="store_true", help="Bind the cloud-audio target locally and write its ignored, explicit Firebase deployment config.")
    args = parser.parse_args()
    if not re.fullmatch(r"bedtime-stories-(staging|prod)-[a-z0-9-]+", args.project) or args.bucket != args.project + "-audio":
        parser.error("Only the dedicated environment's exact audio bucket can be registered.")
    import google.auth
    from google.auth.transport.requests import AuthorizedSession
    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    session = AuthorizedSession(credentials)
    project = session.get(f"https://cloudresourcemanager.googleapis.com/v1/projects/{args.project}", timeout=30)
    bucket = session.get(f"https://storage.googleapis.com/storage/v1/b/{args.bucket}", timeout=30)
    if project.status_code != 200 or bucket.status_code != 200 or str(bucket.json().get("projectNumber")) != str(project.json().get("projectNumber")):
        print(json.dumps({"errorCode": "bucket_project_ownership_unverified"}))
        return 1
    url = f"https://firebasestorage.googleapis.com/v1beta/projects/{args.project}/buckets/{args.bucket}"
    linked = session.get(url, timeout=30)
    if linked.status_code == 404 and args.register:
        linked = session.post(url + ":addFirebase", json={}, timeout=30)
        if linked.status_code not in {200, 409}:
            print(json.dumps({"errorCode": "firebase_bucket_registration_failed", "status": linked.status_code}))
            return 1
        linked = session.get(url, timeout=30)
    if linked.status_code != 200:
        print(json.dumps({"project": args.project, "bucket": args.bucket, "linked": False, "status": linked.status_code}))
        return 1
    if args.configure_cli:
        root = Path(__file__).resolve().parents[2]
        # An alternate config beside firebase.json keeps all relative source/rules paths unchanged.
        configuration = json.loads((root / "firebase.json").read_text())
        configuration["storage"] = [{"target": "cloud-audio", "rules": "backend/storage.rules"}]
        target = root / f".env.firebase.{args.project}.json"
        target.write_text(json.dumps(configuration, indent=2) + "\n")
        subprocess.run(["firebase", "target:apply", "storage", "cloud-audio", args.bucket,
                        "--project", args.project, "--config", str(target)], cwd=root, check=True)
        print(json.dumps({"deploymentConfig": str(target), "storageTarget": "cloud-audio"}))
    print(json.dumps({"project": args.project, "bucket": args.bucket, "linked": True}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        # Credential/transport exceptions can contain tokens; expose only an operational code.
        print(json.dumps({"errorCode": "registration_or_cli_configuration_failed"}))
        raise SystemExit(1)
