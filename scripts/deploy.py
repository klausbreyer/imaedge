#!/usr/bin/env python3
"""Deploy an immutable image while preserving Bunny's runtime secrets."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_ENV = (
    "DATABASE_URL", "SECRET_KEY_BASE", "ADMIN_USERNAME", "ADMIN_PASSWORD",
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_ENDPOINT_URL_S3", "BUCKET_NAME",
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def api(method, path, body=None):
    # Capture responses and errors because either can contain runtime secrets.
    result = subprocess.run(
        ["bunny", "api", method, path],
        input=json.dumps(body) if body is not None else "",
        capture_output=True, text=True, timeout=90,
    )
    require(result.returncode == 0, f"Bunny API failed: {method} {path}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def validate_app(app, config):
    """Local upload chunks and PubSub require one node, including during updates."""
    require(app["autoScaling"] == {"min": 1, "max": 1}, "Expected exactly one replica.")
    for key in ("allowedRegionIds", "requiredRegionIds"):
        require(app["regionSettings"][key] == [config["region"]], "Expected one fixed region.")
    require(len(app["containerTemplates"]) == 1, "Expected one container.")
    container = app["containerTemplates"][0]
    require(container["name"] == "app", "Unexpected container name.")
    require((container["imageNamespace"], container["imageName"]) ==
            ("klausbreyer", "imaedge"), "Unexpected application image.")
    require(app["volumes"] == [{"name": "single-instance", "size": 1}],
            "Expected the single-instance volume for stop-before-start updates.")
    require(container["volumeMounts"] ==
            [{"name": "single-instance", "mountPath": "/var/lib/imaedge"}],
            "The single-instance volume must stay mounted.")
    environment = {item["name"]: item["value"] for item in container["environmentVariables"]}
    for name in REQUIRED_ENV:
        require(bool(environment.get(name)), f"Missing runtime setting: {name}")
    require(environment["BUCKET_NAME"] == "imaedge-prod", "Refusing a different production bucket.")
    return container


def ready_pod(overview, image_digest=None):
    pods = [pod for region in overview["regions"] for pod in region["pods"]]
    ready = [pod for pod in pods if pod["status"] == "ready"]
    require(len(ready) <= 1, "More than one ready pod detected.")
    if overview["status"] == "active" and len(pods) == len(ready) == 1:
        if image_digest is not None and not any(
            container["status"] == "ready" and container["image"].endswith("@" + image_digest)
            for container in ready[0]["containers"]
        ):
            return None
        return ready[0]["name"]
    return None


def desired_patch(container, config, tag, digest, storage=None):
    # Preserve app secrets. Storage credentials come from the configured Bunny zone.
    environment = {item["name"]: item["value"] for item in container["environmentVariables"]}
    environment.update(config["environment"])
    if storage is not None:
        environment.update(storage)
        environment.pop("TIGRIS_PUBLIC_BASE_URL", None)
    return {
        "imageTag": tag, "imageDigest": digest, "imagePullPolicy": "always",
        "environmentVariables": [{"name": name, "value": value}
                                 for name, value in sorted(environment.items())],
    }


def deploy(check_only=False):
    app_id = os.environ.get("BUNNY_APP_ID", "")
    require(bool(re.fullmatch(r"[A-Za-z0-9]+", app_id)), "Set BUNNY_APP_ID.")
    config = json.loads((ROOT / "bunny.json").read_text())
    base = "/mc/apps/" + app_id
    app = api("GET", base)
    container = validate_app(app, config)
    old_pod = ready_pod(api("GET", base + "/overview"))
    if check_only:
        require(old_pod is not None, "Application is not ready.")
        print(f"One ready pod: {old_pod}. Configuration verified.")
        return

    tag = os.environ.get("IMAGE_TAG", "")
    digest = os.environ.get("IMAGE_DIGEST", "")
    require(bool(re.fullmatch(r"[a-f0-9]{40}", tag)), "Expected a full commit SHA image tag.")
    require(bool(re.fullmatch(r"sha256:[a-f0-9]{64}", digest)), "Expected an image digest.")
    image = api("POST", "/mc/registries/digest", {
        "registryId": container["imageRegistryId"], "imageNamespace": "klausbreyer",
        "imageName": "imaedge", "tag": tag,
    })
    require(image["digest"] == digest, "Registry digest differs from the built image.")
    storage = storage_environment(config["storage"], api("GET", "/storagezone/" + str(config["storage"]["zone_id"])))
    patch = desired_patch(container, config, tag, digest, storage)
    changed = any(container.get(key) != value for key, value in patch.items())
    replace_pod = requires_replacement(container, patch)
    require(old_pod is not None or app["status"] == "inactive",
            "App is unhealthy or updating. Inspect Bunny before deploying.")
    if changed:
        api("PATCH", base + "/containers/" + container["id"], patch)
    if app["status"] == "inactive":
        api("POST", base + "/deploy")
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        overview = api("GET", base + "/overview")
        pod = ready_pod(overview, digest)
        if pod and (not replace_pod or pod != old_pod):
            live = validate_app(api("GET", base), config)
            require(live["imageDigest"] == digest, "Deployed image changed unexpectedly.")
            require(not requires_replacement(live, patch), "Runtime settings changed unexpectedly.")
            print(f"Deployment ready: {pod}, imaedge:{tag} ({digest}).", flush=True)
            return
        time.sleep(5)
    raise RuntimeError("Deployment did not finish within 15 minutes. Inspect Bunny before retrying.")


def requires_replacement(container, patch):
    # Bunny keeps the pod when only a tag changes and its image digest is identical.
    environment = lambda settings: {item["name"]: item["value"]
                                    for item in settings["environmentVariables"]}
    return (container["imageDigest"] != patch["imageDigest"] or
            container.get("imagePullPolicy") != patch["imagePullPolicy"] or
            environment(container) != environment(patch))


def storage_environment(config, zone):
    require(zone["Id"] == config["zone_id"] and zone["Name"] == config["zone_name"],
            "Unexpected Bunny storage zone.")
    require(config["zone_name"] == "imaedge-prod", "Expected the production storage zone.")
    require(zone["Region"].lower() == config["region"] and
            "https://" + zone["S3Hostname"] == config["endpoint"], "Unexpected storage endpoint.")
    require(bool(zone.get("Password")), "Missing storage credentials.")
    return {"AWS_ACCESS_KEY_ID": zone["Name"], "AWS_SECRET_ACCESS_KEY": zone["Password"],
            "AWS_ENDPOINT_URL_S3": config["endpoint"], "AWS_REGION": config["region"],
            "BUCKET_NAME": zone["Name"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Read-only configuration and readiness check")
    args = parser.parse_args()
    try:
        deploy(args.check)
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
