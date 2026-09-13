#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
NODE_IP="${1:?Node IP required}"
PACKAGE_VERSION="${2:?Kubernetes package version required}"
[[ "$NODE_IP" =~ ^192\.168\.57\.(10|11|12)$ ]]
[[ "$PACKAGE_VERSION" == 1.34.11-1.1 ]]
[[ "$(id -u)" == 0 && -f /etc/os-release ]]
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]]

# Never reconcile packages or runtime configuration over an exercise or upgrade.
if [[ -f /var/lib/cka-lab/bootstrap-complete ]]; then
  printf 'Bootstrap already completed; preserving node configuration.\n'
  exit 0
fi
if [[ -e /etc/kubernetes/kubelet.conf ]]; then
  printf 'ERROR: refusing to provision an existing, unowned cluster node.\n' >&2
  exit 1
fi

swapoff -a
sed -i '/^[^#].*[[:space:]]swap[[:space:]]/s/^/# cka-lab: /' /etc/fstab
cat >/etc/modules-load.d/cka-lab.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-cka-lab.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
sed -i '/# cka-lab-start/,/# cka-lab-end/d' /etc/hosts
cat >>/etc/hosts <<'EOF'
# cka-lab-start
192.168.57.10 controlplane
192.168.57.11 node01
192.168.57.12 node02
# cka-lab-end
EOF

apt-get update
apt-get install -y ca-certificates curl gpg containerd jq vim bash-completion
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key |
  gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat >/etc/apt/sources.list.d/kubernetes.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /
EOF
apt-get update
apt-get install -y kubelet="$PACKAGE_VERSION" kubeadm="$PACKAGE_VERSION" \
  kubectl="$PACKAGE_VERSION" cri-tools
apt-mark hold kubelet kubeadm kubectl
printf 'KUBELET_EXTRA_ARGS=--node-ip=%s\n' "$NODE_IP" >/etc/default/kubelet
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
systemctl enable kubelet

ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == arm64 || "$ARCH" == amd64 ]]
TMP="$(mktemp -d)"
trap 'rm -f "$TMP/etcd.tar.gz" "$TMP/SHA256SUMS"; rmdir "$TMP"' EXIT
curl -fsSL --retry 3 -o "$TMP/etcd.tar.gz" \
  "https://github.com/etcd-io/etcd/releases/download/v3.6.5/etcd-v3.6.5-linux-$ARCH.tar.gz"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" \
  https://github.com/etcd-io/etcd/releases/download/v3.6.5/SHA256SUMS
EXPECTED="$(awk -v file="etcd-v3.6.5-linux-$ARCH.tar.gz" '$2 == file {print $1}' "$TMP/SHA256SUMS")"
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]]
printf '%s  %s\n' "$EXPECTED" "$TMP/etcd.tar.gz" | sha256sum -c -
tar -xzf "$TMP/etcd.tar.gz" -C /usr/local/bin --strip-components=1 \
  "etcd-v3.6.5-linux-$ARCH/etcdctl" "etcd-v3.6.5-linux-$ARCH/etcdutl"

cat >/etc/profile.d/cka-lab.sh <<'EOF'
if [ -n "${BASH_VERSION:-}" ]; then
  alias k=kubectl
  export do='--dry-run=client -o yaml'
  export now='--force --grace-period=0'
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi
EOF
for home in /home/vagrant /root; do
  printf 'set expandtab\nset tabstop=2\nset shiftwidth=2\nset number\nset autoindent\n' >"$home/.vimrc"
done
chown vagrant:vagrant /home/vagrant/.vimrc
install -d -m 0755 /var/lib/cka-lab
touch /var/lib/cka-lab/bootstrap-complete
