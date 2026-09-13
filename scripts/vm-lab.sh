#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.lab/vms"
export VAGRANT_CWD="$ROOT/lab/vms"
export VAGRANT_DOTFILE_PATH="$STATE/vagrant"
export KUBECONFIG="$STATE/kubeconfig"
export PATH="$STATE/bin:$PATH"
CONTEXT=kubernetes-admin@kubernetes
NODES=(controlplane node01 node02)

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Falta '$1'. Consulta lab/vms/README.md."; }
v() { vagrant "$@"; }
k() { kubectl --kubeconfig "$KUBECONFIG" --context "$CONTEXT" "$@"; }
h() { helm --kubeconfig "$KUBECONFIG" --kube-context "$CONTEXT" "$@"; }

usage() {
  cat <<'EOF'
Uso: bash scripts/vm-lab.sh COMANDO
  doctor           Comprueba Vagrant, VirtualBox y recursos, sin crear VMs
  up               Arranca/provisiona VMs, inicia kubeadm y une workers
  machines         Crea solo VMs con paquetes; no ejecuta init/join ni CNI
  addons           Instala/reconcilia Calico, metricas, storage y routing
  status           Muestra VMs, nodos, complementos y metricas
  check            Comprueba SSH, paquetes y el comportamiento del cluster
  shell            Abre Bash macOS con kubectl 1.35 y kubeconfig aislado
  node cp|w1|w2    Abre SSH como vagrant; usa sudo -i para administrar Linux
  kubectl ARGS...  Ejecuta kubectl contra las VMs
  helm ARGS...     Ejecuta Helm contra las VMs
  stop             Apaga solo las tres VMs, conservando discos y ejercicios
  start            Arranca VMs sin provisionar ni reconciliar el cluster
  down --yes       BORRA solo estas tres VMs y sus discos
  reset full --yes BORRA y reconstruye el cluster completo en Kubernetes 1.34
  reset bare --yes BORRA y crea VMs sin init/join ni CNI para practicar instalacion
  help             Muestra esta ayuda
EOF
}

owned() {
  [[ -f "$STATE/owner" && "$(<"$STATE/owner")" == "$ROOT" ]] ||
    fail "No hay VMs registradas para este repositorio. Ejecuta machines o up."
}

require_lab() {
  owned
  need kubectl
  [[ -s "$KUBECONFIG" ]] || fail "No hay kubeconfig del cluster. Ejecuta up."
  [[ "$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')" == https://192.168.57.10:6443 ]] ||
    fail "El kubeconfig no apunta a la API privada esperada."
}

doctor() {
  local tool
  for tool in vagrant VBoxManage curl shasum; do need "$tool"; done
  [[ "$(uname -s)" == Darwin ]] || fail "Este laboratorio esta preparado para macOS."
  v --version
  VBoxManage --version
  v validate
  printf 'Reserva: 8 GiB RAM, 6 vCPU virtuales y al menos 30 GiB de disco libre.\n'
  printf 'Red host-only: 192.168.57.0/24; pods: 172.20.0.0/16.\n'
  printf 'Estado privado: %s\n' "$STATE"
}

client() {
  local arch tmp expected
  [[ -x "$STATE/bin/kubectl" ]] && return
  arch="$(uname -m)"
  case "$arch" in arm64) ;; x86_64) arch=amd64 ;; *) fail "Arquitectura no soportada: $arch" ;; esac
  mkdir -p "$STATE/bin"
  tmp="$STATE/bin/kubectl.download"
  curl -fsSL --retry 3 -o "$tmp" "https://dl.k8s.io/release/v1.35.8/bin/darwin/$arch/kubectl"
  expected="$(curl -fsSL --retry 3 "https://dl.k8s.io/release/v1.35.8/bin/darwin/$arch/kubectl.sha256")"
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || fail "Checksum kubectl invalido."
  printf '%s  %s\n' "$expected" "$tmp" | shasum -a 256 -c -
  chmod 700 "$tmp"
  mv "$tmp" "$STATE/bin/kubectl"
}

machines() {
  doctor
  umask 077
  mkdir -p "$STATE"
  chmod 700 "$STATE"
  if [[ -e "$STATE/owner" ]]; then
    owned
  else
    # `vagrant validate` creates empty machine directories before any VM exists.
    if [[ -d "$VAGRANT_DOTFILE_PATH/machines" ]] &&
       [[ -n "$(find "$VAGRANT_DOTFILE_PATH/machines" -type f -print -quit)" ]]; then
      fail "Estado Vagrant sin propietario; no se adoptara."
    fi
    local existing node
    existing="$(VBoxManage list vms)"
    for node in "${NODES[@]}"; do
      if printf '%s\n' "$existing" | grep -q "\"cka-vm-$node\""; then
        fail "Ya existe cka-vm-$node fuera de este laboratorio; no se adoptara."
      fi
    done
    printf '%s\n' "$ROOT" >"$STATE/owner"
  fi
  client
  v up --provider=virtualbox --no-parallel --no-destroy-on-error "${NODES[@]}"
}

up() {
  machines
  v ssh controlplane -c 'sudo bash -s' <"$ROOT/lab/vms/init.sh"
  umask 077
  local tmp token endpoint hash node joined
  tmp="$(mktemp "$STATE/kubeconfig.XXXXXX")"
  if ! v ssh controlplane -c 'sudo cat /etc/kubernetes/admin.conf' >"$tmp"; then
    rm -f "$tmp"
    fail "No se pudo obtener el kubeconfig."
  fi
  if [[ "$(kubectl --kubeconfig "$tmp" config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != https://192.168.57.10:6443 ]]; then
    rm -f "$tmp"
    fail "Kubeconfig inesperado; no se guardara."
  fi
  mv "$tmp" "$KUBECONFIG"
  require_lab
  for node in node01 node02; do
    joined="$(v ssh "$node" -c 'if sudo test -f /etc/kubernetes/kubelet.conf; then printf joined; else printf new; fi')"
    case "$joined" in
      joined) printf '%s ya unido; se conserva su configuracion.\n' "$node"; continue ;;
      new) ;;
      *) fail "Estado inesperado para $node: $joined" ;;
    esac
    # Parse only the expected kubeadm output; never execute a generated shell command.
    local join_command
    join_command="$(v ssh controlplane -c 'sudo kubeadm token create --ttl 15m --print-join-command')"
    read -r _ _ endpoint _ token _ hash <<<"$join_command"
    [[ "$endpoint" == 192.168.57.10:6443 && "$token" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ &&
       "$hash" =~ ^sha256:[a-f0-9]{64}$ ]] || fail "Respuesta join inesperada."
    printf '%s\n%s\n' "$token" "$hash" |
      v ssh "$node" -c 'read -r token; read -r hash; sudo kubeadm join 192.168.57.10:6443 --token "$token" --discovery-token-ca-cert-hash "$hash" --cri-socket unix:///run/containerd/containerd.sock'
  done
  if [[ ! -f "$STATE/addons-complete" ]]; then
    addons
  fi
  printf '\nCluster disponible. Entrar por SSH: bash scripts/vm-lab.sh node cp\n'
  k get nodes -o wide
}

addons() {
  require_lab
  need helm
  helm template calico-crds crd.projectcalico.org.v1 \
    --repo https://docs.tigera.io/calico/charts --version v3.32.2 |
    k apply --server-side -f -
  k wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
  h upgrade --install calico tigera-operator \
    --repo https://docs.tigera.io/calico/charts --version v3.32.2 \
    --namespace tigera-operator --create-namespace \
    -f "$ROOT/lab/vms/calico-values.yaml" --wait --timeout 10m
  k wait --for=create daemonset/calico-node -n calico-system --timeout=300s
  k rollout status daemonset/calico-node -n calico-system --timeout=300s
  k wait --for=condition=Ready nodes --all --timeout=300s
  k rollout status deployment/calico-kube-controllers -n calico-system --timeout=300s
  k rollout status deployment/coredns -n kube-system --timeout=180s
  k apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml
  k patch storageclass local-path --type=merge \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
  k apply -f "$ROOT/lab/vms/storageclass.yaml"
  k -n local-path-storage rollout status deployment/local-path-provisioner --timeout=180s
  k apply -k "$ROOT/lab/metrics"
  k rollout status deployment/metrics-server -n kube-system --timeout=300s
  k wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=180s
  k apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
  k wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=60s
  h upgrade --install traefik oci://ghcr.io/traefik/helm/traefik \
    --version 41.5.0 --namespace traefik --create-namespace \
    -f "$ROOT/lab/traefik-values.yaml" --wait --timeout 5m
  k apply -f "$ROOT/lab/gatewayclass.yaml"
  k wait --for=condition=Accepted gatewayclass/traefik --timeout=120s
  touch "$STATE/addons-complete"
}

check_cluster() {
  require_lab
  local node
  for node in "${NODES[@]}"; do
    v ssh "$node" -c 'set -e; systemctl is-active kubelet containerd; test -z "$(swapon --show --noheadings)"; dpkg-query -W kubeadm kubelet kubectl; sudo crictl info >/dev/null; etcdutl version'
  done
  k rollout status deployment/calico-kube-controllers -n calico-system --timeout=180s
  export CKA_LAB_BACKEND=vms
  bash "$ROOT/scripts/check-lab.sh"
}

destroy() {
  owned
  printf 'Borrando SOLO controlplane, node01 y node02 de este laboratorio.\n'
  printf 'Se pierden discos/PVC y archivos dentro de Ubuntu; .lab/answers/ se conserva.\n'
  v destroy --force "${NODES[@]}"
  rm -f "$STATE/kubeconfig" "$STATE/addons-complete"
}

command="${1:-help}"
[[ $# -eq 0 ]] || shift
case "$command" in
  help|-h|--help) usage ;;
  doctor|machines|up|addons|status|check|shell|stop|start)
    [[ $# -eq 0 ]] || fail "$command no acepta argumentos."
    case "$command" in
      doctor|machines|up|addons) "$command" ;;
      start|stop)
        owned
        if [[ "$command" == start ]]; then
          v up --provider=virtualbox --no-provision "${NODES[@]}"
        else
          v halt "${NODES[@]}"
        fi
        ;;
      status)
        owned
        v status
        require_lab
        k get nodes -o wide
        k get pods -A
        k get storageclass,ingressclass,gatewayclass
        k top nodes
        ;;
      shell)
        require_lab
        export CKA_LAB_ROOT="$ROOT" CKA_LAB_BACKEND=vms
        exec bash --noprofile --rcfile "$ROOT/lab/bashrc" -i
        ;;
      check)
        check_cluster
        ;;
    esac
    ;;
  kubectl|helm)
    require_lab
    if [[ "$command" == kubectl ]]; then k "$@"; else need helm; h "$@"; fi
    ;;
  node)
    [[ $# -eq 1 ]] || fail "Indica cp, w1 o w2."
    case "$1" in cp) node=controlplane ;; w1) node=node01 ;; w2) node=node02 ;; *) fail "Nodo no permitido." ;; esac
    owned
    exec vagrant ssh "$node"
    ;;
  down)
    [[ $# -eq 1 && "$1" == --yes ]] || fail "Borrado requiere: down --yes"
    destroy
    ;;
  reset)
    [[ $# -eq 2 && "$2" == --yes ]] || fail "Recreacion requiere: reset full|bare --yes"
    [[ "$1" == full || "$1" == bare ]] || fail "Modo no permitido: usa full o bare."
    owned
    doctor
    destroy
    if [[ "$1" == full ]]; then
      up
      check_cluster
      printf '\nReset completo: cluster 1.34 reconstruido y comprobado.\n'
    else
      machines
      printf '\nReset bare completo: Ubuntu y paquetes listos; practica init/join y un unico CNI.\n'
    fi
    ;;
  *) fail "Comando desconocido: $command" ;;
esac
