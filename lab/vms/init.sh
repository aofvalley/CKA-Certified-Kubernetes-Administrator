#!/bin/bash
set -euo pipefail
[[ "$(hostname)" == controlplane && -f /var/lib/cka-lab/bootstrap-complete ]]
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  if [[ -e /etc/kubernetes/manifests/kube-apiserver.yaml || -d /var/lib/etcd/member ]]; then
    printf 'ERROR: partial control plane detected; inspect it before retrying init.\n' >&2
    exit 1
  fi
  kubeadm init --kubernetes-version=v1.34.11 \
    --skip-token-print --token-ttl=15m \
    --apiserver-advertise-address=192.168.57.10 \
    --control-plane-endpoint=192.168.57.10:6443 \
    --pod-network-cidr=172.20.0.0/16 \
    --service-cidr=10.96.0.0/12 \
    --cri-socket=unix:///run/containerd/containerd.sock
fi
install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.kube
install -m 0600 -o vagrant -g vagrant /etc/kubernetes/admin.conf /home/vagrant/.kube/config
install -d -m 0700 /root/.kube
install -m 0600 /etc/kubernetes/admin.conf /root/.kube/config
