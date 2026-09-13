import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class ConfigurationTests(unittest.TestCase):
    def test_all_lab_yaml_parses(self):
        for path in (ROOT / "lab").rglob("*.yaml"):
            with self.subTest(path=path), path.open() as stream:
                self.assertTrue(list(yaml.safe_load_all(stream)))

    def test_cluster_is_multinode_and_local(self):
        config = yaml.safe_load((ROOT / "lab/kind.yaml").read_text())
        self.assertEqual(
            [node["role"] for node in config["nodes"]],
            ["control-plane", "worker", "worker"],
        )
        self.assertEqual(config["networking"]["apiServerAddress"], "127.0.0.1")
        self.assertTrue(config["networking"]["disableDefaultCNI"])
        calico = yaml.safe_load((ROOT / "lab/calico-values.yaml").read_text())
        pool = calico["installation"]["calicoNetwork"]["ipPools"][0]
        self.assertEqual(pool["cidr"], config["networking"]["podSubnet"])

    def test_routing_classes_and_ports_match(self):
        config = yaml.safe_load((ROOT / "lab/traefik-values.yaml").read_text())
        self.assertEqual(config["service"]["spec"]["type"], "ClusterIP")
        routes = list(yaml.safe_load_all((ROOT / "lab/check/routes.yaml").read_text()))
        self.assertEqual(routes[0]["spec"]["listeners"][0]["port"], config["ports"]["web"]["port"])
        self.assertEqual(routes[2]["spec"]["ingressClassName"], config["ingressClass"]["name"])
        gateway_class = yaml.safe_load((ROOT / "lab/gatewayclass.yaml").read_text())
        self.assertEqual(routes[0]["spec"]["gatewayClassName"], gateway_class["metadata"]["name"])

    def test_guide_local_links_exist(self):
        for guide in (ROOT / "lab").rglob("*.md"):
            for target in re.findall(r"\]\(([^)]+)\)", guide.read_text()):
                if not target.startswith(("https://", "#")):
                    with self.subTest(guide=guide, target=target):
                        self.assertTrue((guide.parent / target.split("#")[0]).exists())


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(ROOT / "scripts/lab.sh", self.root / "scripts/lab.sh")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        stub = f"""#!{sys.executable}
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([tool, args, os.environ.get("KUBECONFIG")]) + "\\n")
if tool == "docker":
    if args[:2] == ["context", "show"]:
        print("desktop-linux")
    elif args[:2] == ["context", "inspect"]:
        print(os.environ.get("ENDPOINT", "unix:///tmp/docker.sock"))
    elif args and args[0] == "info" and "MemTotal" in " ".join(args):
        print(os.environ.get("MEMORY", "8000000000"))
elif tool == "kind":
    if args == ["version"]:
        print(os.environ.get("KIND_VERSION", "kind v0.32.0 go1.26.3 darwin/arm64"))
    elif args == ["get", "clusters"]:
        print(os.environ.get("CLUSTERS", ""))
elif tool == "kubectl" and "view" in args:
    print(os.environ.get("SERVER", "https://127.0.0.1:45678"))
"""
        for tool in ("docker", "kind", "kubectl", "helm", "curl"):
            path = self.bin / tool
            path.write_text(stub)
            path.chmod(0o755)
        self.env = dict(os.environ)
        self.env.pop("DOCKER_HOST", None)
        self.env.update(
            PATH=f"{self.bin}:/usr/bin:/bin",
            CALL_LOG=str(self.log),
            KUBECONFIG="/do-not-touch/global-config",
        )

    def run_lab(self, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts/lab.sh"), *args],
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
        )

    def state(self):
        state = self.root / ".lab"
        state.mkdir()
        (state / "kubeconfig").write_text("test-config")
        (state / "docker-context").write_text("desktop-linux\n")

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_help_does_not_contact_docker(self):
        self.assertEqual(self.run_lab("help").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_invalid_commands_and_unconfirmed_deletion_fail(self):
        for args in [("oops",), ("down",), ("down", "--yes", "extra"), ("node", "other"), ("up", "extra")]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_lab(*args).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_missing_lab_fails_without_cluster_access(self):
        result = self.run_lab("kubectl", "get", "nodes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No hay laboratorio", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_kubectl_uses_only_lab_config(self):
        self.state()
        result = self.run_lab("kubectl", "get", "nodes")
        self.assertEqual(result.returncode, 0, result.stderr)
        tool, args, config = self.calls()[-1]
        self.assertEqual(tool, "kubectl")
        self.assertEqual(config, str(self.root / ".lab/kubeconfig"))
        self.assertEqual(args[:4], ["--kubeconfig", config, "--context", "kind-cka-10days"])
        self.assertEqual(args[4:], ["get", "nodes"])

    def test_remote_kubeconfig_is_refused(self):
        self.state()
        result = self.run_lab("kubectl", "delete", "ns", "test", SERVER="https://remote.example:6443")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("delete" in args for _, args, _ in self.calls()))

    def test_remote_docker_is_refused(self):
        result = self.run_lab("doctor", ENDPOINT="tcp://remote.example:2376")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Docker local", result.stderr)

    def test_old_kind_and_insufficient_memory_fail(self):
        for env in [{"KIND_VERSION": "kind v0.31.0"}, {"MEMORY": "2000000000"}]:
            with self.subTest(env=env):
                self.assertNotEqual(self.run_lab("doctor", **env).returncode, 0)

    def test_existing_unowned_cluster_is_not_adopted(self):
        result = self.run_lab("up", CLUSTERS="cka-10days")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No se modificara", result.stderr)
        self.assertFalse(any("apply" in args or "upgrade" in args for _, args, _ in self.calls()))

    def test_down_targets_only_owned_cluster(self):
        self.state()
        result = self.run_lab("down", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        deletes = [args for tool, args, _ in self.calls() if tool == "kind"]
        self.assertEqual(deletes, [[
            "delete", "cluster", "--name", "cka-10days",
            "--kubeconfig", str(self.root / ".lab/kubeconfig"),
        ]])
        self.assertFalse((self.root / ".lab/kubeconfig").exists())

    def test_shell_setup_does_not_modify_user_vimrc(self):
        home = self.root / "home"
        home.mkdir()
        vimrc = home / ".vimrc"
        vimrc.write_text("user-owned configuration\n")
        result = subprocess.run(
            ["/bin/bash", "-c", 'source "$1"', "test", str(ROOT / "scripts/exam-setup.sh")],
            env={**self.env, "HOME": str(home), "EXAM_CONFIGURE_VIM": "false"},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(vimrc.read_text(), "user-owned configuration\n")


if __name__ == "__main__":
    unittest.main()
