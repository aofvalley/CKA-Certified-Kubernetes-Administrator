# Exercise 09 — kubeadm Cluster Upgrade

> Related: [Chuleta — upgrade kubeadm](../../cheatsheet/cka-cheatsheet.md#11-upgrade-con-kubeadm) | [Upgrade en las VMs](../../lab/vms/upgrade.md)

Upgrade a cluster from one minor version to the next using kubeadm. The CKA frequently asks this — you need to know the exact sequence.

**Local VM lab:** start with [the Ubuntu/kubeadm lab](../../lab/vms/README.md), which runs 1.34.11. Use the [1.34.11 → 1.35.8 procedure](../../lab/vms/upgrade.md) for this environment: it includes the minor-version apt repository change, control-plane drain and the correct worker upgrade sequence. To repeat, `bash scripts/vm-lab.sh reset full --yes` recreates the three VMs and deletes their data.

## Tasks

1. Check the current cluster version (`k get nodes`, `kubeadm version`)
2. Upgrade the control plane node:
   a. Update the kubeadm package to the target version
   b. Run `kubeadm upgrade plan` to see available upgrades
   c. Run `kubeadm upgrade apply v1.35.x`
   d. Upgrade kubelet and kubectl packages
   e. Restart kubelet
3. Upgrade a worker node:
   a. Drain the worker node
   b. Update kubeadm, kubelet, kubectl packages on the worker
   c. Run `kubeadm upgrade node`
   d. Restart kubelet
   e. Uncordon the worker
4. Verify all nodes show the new version

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Always upgrade control plane first, then workers one at a time
- The package manager commands depend on your OS (apt for Ubuntu, yum for CentOS)
- `kubeadm upgrade plan` shows you what versions are available
- On workers, it's `kubeadm upgrade node` (NOT `kubeadm upgrade apply`)
- Don't forget to drain before upgrading a worker

</details>

## What tripped me up

> After upgrading kubelet, it didn't start. I ran `systemctl restart kubelet` but forgot `systemctl daemon-reload` first. The systemd unit file changed but systemd didn't know about it. Always `daemon-reload` then `restart`. In that order. I lost 4 minutes on this during practice.
>
> On the worker node, I ran `kubeadm upgrade apply` instead of `kubeadm upgrade node`. Apply is for the control plane only. On workers it's `kubeadm upgrade node`. The error message is confusing — it doesn't immediately say "wrong command." It tries to run and fails partway through.
>
> Also: drain the worker BEFORE upgrading it. I upgraded first, then drained, and some pods got killed mid-upgrade when the node restarted. The safe order is: drain → upgrade → restart kubelet → uncordon.

## Verify

```bash
# All nodes should show the new version
k get nodes

# Components should match
kubeadm version
kubelet --version
kubectl version --client
```

## Cleanup

No cleanup needed — this is a one-way upgrade.

<details>
<summary>Solution</summary>

```bash
# === CONTROL PLANE NODE ===

# Check current version
k get nodes
kubeadm version

# Update kubeadm (Ubuntu/Debian example)
sudo apt-mark unhold kubeadm
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm

# Plan
sudo kubeadm upgrade plan

# Apply
sudo kubeadm upgrade apply v1.35.0

# Update kubelet + kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Verify control plane
k get nodes

# === WORKER NODE (run from control plane, then SSH to worker) ===

# From control plane: drain worker
k drain worker-1 --ignore-daemonsets --delete-emptydir-data

# SSH to worker node
ssh worker-1

# Update packages on worker
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1 kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

# Upgrade node config
sudo kubeadm upgrade node

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Exit back to control plane
exit

# Uncordon worker
k uncordon worker-1

# Verify
k get nodes
```

Remember:
- Control plane: `kubeadm upgrade apply`
- Worker: `kubeadm upgrade node`
- Always drain workers before upgrading them
- Always uncordon after

</details>
