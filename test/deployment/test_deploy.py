"""Protect single-node uploads and production secrets during deployments."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("deploy", Path(__file__).resolve().parents[2] / "scripts/deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentTest(unittest.TestCase):
    def setUp(self):
        self.app = {
            "autoScaling": {"min": 1, "max": 1},
            "regionSettings": {"allowedRegionIds": ["DE"], "requiredRegionIds": ["DE"]},
            "volumes": [{"name": "single-instance", "size": 1}],
            "containerTemplates": [{
                "name": "app", "imageNamespace": "klausbreyer", "imageName": "imaedge",
                "volumeMounts": [{"name": "single-instance", "mountPath": "/var/lib/imaedge"}],
                "environmentVariables": [{"name": name, "value": "imaedge-prod" if name == "BUCKET_NAME" else "preserved"}
                                         for name in deploy.REQUIRED_ENV],
            }],
        }

    def test_refuses_scaling_or_missing_stop_before_start_volume(self):
        for key, value in (("autoScaling", {"min": 1, "max": 2}), ("volumes", []),
                           ("regionSettings", {"allowedRegionIds": ["DE", "FR"]})):
            with self.subTest(key=key):
                app = copy.deepcopy(self.app)
                app[key] = value
                with self.assertRaises(RuntimeError):
                    deploy.validate_app(app, {"region": "DE"})

    def test_runtime_credentials_are_preserved(self):
        container = deploy.validate_app(self.app, {"region": "DE"})
        patch = deploy.desired_patch(container, {"environment": {"PHX_HOST": "www.imaedge.org"}}, "new", "digest")
        result = {item["name"]: item["value"] for item in patch["environmentVariables"]}
        self.assertEqual(result["BUCKET_NAME"], "imaedge-prod")
        for name in deploy.REQUIRED_ENV:
            if name != "BUCKET_NAME":
                self.assertEqual(result[name], "preserved")

    def test_old_pod_must_finish_shutdown(self):
        overview = {"status": "active", "regions": [{"pods": [
            {"name": "old", "status": "deleting"}, {"name": "new", "status": "ready"},
        ]}]}
        self.assertIsNone(deploy.ready_pod(overview))
        overview["regions"][0]["pods"][0]["status"] = "ready"
        with self.assertRaises(RuntimeError):
            deploy.ready_pod(overview)


if __name__ == "__main__":
    unittest.main()
