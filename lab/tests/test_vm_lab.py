import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class VmCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(ROOT / "scripts/vm-lab.sh", self.root / "scripts/vm-lab.sh")
        (self.root / "lab/vms").mkdir(parents=True)
        shutil.copy(ROOT / "lab/vms/init.sh", self.root / "lab/vms/init.sh")
        (self.root / "scripts/check-lab.sh").write_text('exit "${CHECK_RESULT:-0}"\n')
        self.state = self.root / ".lab/vms"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        stub = f"""#!{sys.executable}
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([tool, args, os.environ.get("KUBECONFIG"), os.environ.get("VAGRANT_CWD")]) + "\\n")
if tool == "kubectl" and "view" in args:
    print(os.environ.get("SERVER", "https://192.168.57.10:6443"))
elif tool == "VBoxManage" and args == ["list", "vms"]:
    print(os.environ.get("EXISTING_VMS", ""))
elif tool == "vagrant" and args == ["validate"]:
    (pathlib.Path(os.environ["VAGRANT_DOTFILE_PATH"]) / "machines/controlplane/virtualbox").mkdir(parents=True, exist_ok=True)
elif tool == "uname":
    print("Darwin" if "-s" in args else "arm64")
elif tool == "vagrant" and args and args[0] == "destroy":
    sys.exit(int(os.environ.get("DESTROY_RESULT", "0")))
elif tool == "vagrant" and args[:2] == ["ssh", "controlplane"] and "cat /etc/kubernetes/admin.conf" in args[-1]:
    print("test-config")
elif tool == "vagrant" and args and args[0] == "ssh" and "printf joined" in args[-1]:
    print("joined")
"""
        for tool in ("vagrant", "VBoxManage", "kubectl", "helm", "curl", "shasum", "uname"):
            path = self.bin / tool
            path.write_text(stub)
            path.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "CALL_LOG": str(self.log),
            "KUBECONFIG": "/do-not-touch/config",
            "VAGRANT_CWD": "/do-not-touch/vagrant",
        }

    def run_lab(self, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts/vm-lab.sh"), *args],
            env={**self.env, **env}, capture_output=True, text=True, check=False,
        )

    def own(self):
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "owner").write_text(str(self.root) + "\n")
        (self.state / "kubeconfig").write_text("lab-config\n")

    def client(self):
        (self.state / "bin").mkdir(parents=True, exist_ok=True)
        shutil.copy(self.bin / "kubectl", self.state / "bin/kubectl")

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_help_and_invalid_input_do_not_contact_vms(self):
        self.assertEqual(self.run_lab("help").returncode, 0)
        for args in [
            ("bad",), ("down",), ("down", "--yes", "extra"), ("node", "unknown"), ("up", "extra"),
            ("reset",), ("reset", "full"), ("reset", "bare"), ("reset", "other", "--yes"),
            ("reset", "full", "--yes", "extra"),
        ]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_lab(*args).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_unowned_vms_cannot_be_changed(self):
        for args in [("down", "--yes"), ("stop",), ("start",), ("node", "cp"), ("kubectl", "get", "nodes")]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_lab(*args).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_wrong_owner_is_rejected(self):
        self.own()
        (self.state / "owner").write_text("/another/repository\n")
        self.assertNotEqual(self.run_lab("stop").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_kubeconfig_and_vagrant_are_isolated(self):
        self.own()
        result = self.run_lab("kubectl", "get", "nodes")
        self.assertEqual(result.returncode, 0, result.stderr)
        tool, args, config, cwd = self.calls()[-1]
        self.assertEqual(tool, "kubectl")
        self.assertEqual(config, str(self.state / "kubeconfig"))
        self.assertEqual(cwd, str(self.root / "lab/vms"))
        self.assertEqual(args, [
            "--kubeconfig", config, "--context", "kubernetes-admin@kubernetes", "get", "nodes",
        ])

    def test_remote_server_is_rejected(self):
        self.own()
        result = self.run_lab("kubectl", "delete", "ns", "test", SERVER="https://remote.example:6443")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("delete" in call[1] for call in self.calls()))

    def test_start_does_not_reprovision(self):
        self.own()
        result = self.run_lab("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1][1], [
            "up", "--provider=virtualbox", "--no-provision", "controlplane", "node01", "node02",
        ])

    def test_down_is_scoped_and_preserves_answers(self):
        self.own()
        answers = self.root / ".lab/answers"
        answers.mkdir()
        (answers / "answer.yaml").write_text("data")
        result = self.run_lab("down", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1][1], ["destroy", "--force", "controlplane", "node01", "node02"])
        self.assertFalse((self.state / "kubeconfig").exists())
        self.assertTrue((answers / "answer.yaml").exists())

    def test_failed_destroy_preserves_config(self):
        self.own()
        result = self.run_lab("down", "--yes", DESTROY_RESULT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.state / "kubeconfig").exists())

    def test_validation_empty_directories_are_not_unowned_machines(self):
        self.client()
        result = self.run_lab("machines")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.state / "owner").exists())
        self.assertTrue(any(call[0] == "vagrant" and call[1][0] == "up" for call in self.calls()))

    def test_unowned_machine_metadata_is_not_adopted(self):
        machine = self.state / "vagrant/machines/controlplane/virtualbox"
        machine.mkdir(parents=True)
        (machine / "id").write_text("unowned-id")
        result = self.run_lab("machines")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "vagrant" and call[1][0] == "up" for call in self.calls()))

    def test_existing_named_vm_is_not_adopted(self):
        result = self.run_lab("machines", EXISTING_VMS='"cka-vm-controlplane" {unowned-id}')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.state / "owner").exists())

    def test_bare_reset_destroys_then_creates_without_cluster_bootstrap(self):
        self.own()
        self.client()
        (self.state / "addons-complete").touch()
        result = self.run_lab("reset", "bare", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [call[1][0] for call in self.calls() if call[0] == "vagrant"]
        self.assertLess(operations.index("destroy"), operations.index("up"))
        self.assertNotIn("ssh", operations)
        self.assertFalse((self.state / "kubeconfig").exists())
        self.assertFalse((self.state / "addons-complete").exists())

    def test_full_reset_rebuilds_addons_and_checks_cluster(self):
        self.own()
        self.client()
        result = self.run_lab("reset", "full", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.state / "addons-complete").exists())
        self.assertIn("reconstruido y comprobado", result.stdout)
        self.assertEqual(sum(
            call[0] == "vagrant" and call[1][0] == "ssh" and "systemctl is-active" in call[1][-1]
            for call in self.calls()
        ), 3)

    def test_reset_stops_when_deletion_fails(self):
        self.own()
        result = self.run_lab("reset", "full", "--yes", DESTROY_RESULT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "vagrant" and call[1][0] == "up" for call in self.calls()))

    def test_reset_does_not_report_success_when_check_fails(self):
        self.own()
        self.client()
        result = self.run_lab("reset", "full", "--yes", CHECK_RESULT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("reconstruido y comprobado", result.stdout)


class VmConfigurationTests(unittest.TestCase):
    def test_vm_pod_network_does_not_overlap_node_network(self):
        import ipaddress
        calico = yaml.safe_load((ROOT / "lab/vms/calico-values.yaml").read_text())
        network = calico["installation"]["calicoNetwork"]
        pod_cidr = network["ipPools"][0]["cidr"]
        node_cidr = network["nodeAddressAutodetectionV4"]["cidrs"][0]
        self.assertFalse(ipaddress.ip_network(pod_cidr).overlaps(ipaddress.ip_network(node_cidr)))
        self.assertIn(f"--pod-network-cidr={pod_cidr}", (ROOT / "lab/vms/init.sh").read_text())
        self.assertNotIn("kubernetesProvider", calico["installation"])

    def test_vm_storage_matches_functional_test(self):
        storage = yaml.safe_load((ROOT / "lab/vms/storageclass.yaml").read_text())
        workloads = list(yaml.safe_load_all((ROOT / "lab/check/workloads.yaml").read_text()))
        self.assertEqual(storage["metadata"]["name"], workloads[0]["spec"]["storageClassName"])
        self.assertEqual(storage["volumeBindingMode"], "WaitForFirstConsumer")

    def test_bootstrap_exits_before_mutation_on_completed_nodes(self):
        bootstrap = (ROOT / "lab/vms/bootstrap.sh").read_text()
        self.assertLess(bootstrap.index("bootstrap-complete"), bootstrap.index("swapoff -a"))
        self.assertIn("apt-mark hold kubelet kubeadm kubectl", bootstrap)
        self.assertIn("1.34.11-1.1", bootstrap)
        self.assertIn("1.34.11-1.1", (ROOT / "lab/vms/Vagrantfile").read_text())


if __name__ == "__main__":
    unittest.main()
