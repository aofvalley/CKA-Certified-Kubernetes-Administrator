#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.lab"
CLUSTER=cka-10days
CONTEXT="kind-$CLUSTER"
NODE_IMAGE="kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95"
export KUBECONFIG="$STATE/kubeconfig"
export KIND_EXPERIMENTAL_PROVIDER=docker

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Falta '$1'. Consulta lab/README.md."; }
k() { kubectl --kubeconfig "$KUBECONFIG" --context "$CONTEXT" "$@"; }
h() { helm --kubeconfig "$KUBECONFIG" --kube-context "$CONTEXT" "$@"; }

usage() {
  cat <<'EOF'
Uso: bash scripts/lab.sh COMANDO
  doctor           Comprueba herramientas y Docker (no modifica clusters)
  up               Crea 3 nodos e instala/reconcilia los complementos
  status           Muestra nodos, complementos, clases y metricas
  check            Prueba DNS, HTTP entre nodos, NetworkPolicy, PVC y rutas
  shell            Abre Bash aislado con aliases, completion y Vim para YAML
  kubectl ARGS...  Ejecuta kubectl contra el laboratorio
  helm ARGS...     Ejecuta Helm contra el laboratorio
  node cp|w1|w2    Abre Bash dentro de un nodo Linux (no en macOS)
  down --yes       BORRA solo cka-10days, incluidos ejercicios y volumenes
  help             Muestra esta ayuda
EOF
}

docker_ready() {
  need docker
  # Reuse the original local daemon even if the user's active context changes.
  if [[ -f "$STATE/docker-context" ]]; then
    export DOCKER_CONTEXT
    DOCKER_CONTEXT="$(<"$STATE/docker-context")"
  else
    [[ -z "${DOCKER_HOST:-}" ]] || fail "Desactiva DOCKER_HOST; se requiere un contexto Docker local."
    export DOCKER_CONTEXT
    DOCKER_CONTEXT="$(docker context show)"
  fi
  local endpoint
  endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')"
  [[ "$endpoint" == unix://* ]] || fail "Se requiere Docker local, no $endpoint."
  docker info >/dev/null 2>&1 || fail "Docker no responde. En macOS: docker desktop start"
}

require_lab() {
  need kubectl
  [[ -s "$KUBECONFIG" && -s "$STATE/docker-context" ]] ||
    fail "No hay laboratorio configurado. Ejecuta: bash scripts/lab.sh up"
  local server
  server="$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  [[ "$server" == https://127.0.0.1:* ]] || fail "El kubeconfig no apunta a la API local esperada."
}

doctor() {
  local tool kind_version memory
  for tool in docker kind kubectl helm curl; do need "$tool"; done
  docker_ready
  kind_version="$(kind version)"
  printf '%s\n' "$kind_version"
  [[ "$kind_version" =~ ^kind\ v([0-9]+)\.([0-9]+)\. ]] || fail "Version de kind no reconocida."
  if (( BASH_REMATCH[1] == 0 && BASH_REMATCH[2] < 32 )); then
    fail "La imagen fijada requiere kind >= 0.32."
  fi
  memory="$(docker info --format '{{.MemTotal}}')"
  [[ "$memory" =~ ^[0-9]+$ ]] || fail "No se pudo consultar la RAM de Docker."
  (( memory >= 6000000000 )) || fail "Asigna al menos 6 GB de RAM a Docker (8 GB recomendado)."
  kubectl version --client
  helm version --short
  docker info --format 'Docker: {{.ServerVersion}} | CPU: {{.NCPU}} | RAM bytes: {{.MemTotal}}'
  printf 'Necesario: kind >= 0.32, Docker con al menos 6 GB de RAM (8 GB recomendado).\n'
  printf 'Cluster: %s | Kubeconfig aislado: %s\n' "$CLUSTER" "$KUBECONFIG"
}

status() {
  require_lab
  k get nodes -o wide
  k get pods -A
  k get storageclass,ingressclass,gatewayclass
  k top nodes
}

up() {
  doctor
  local clusters
  clusters="$(kind get clusters)"
  if printf '%s\n' "$clusters" | grep -qx "$CLUSTER"; then
    [[ -s "$STATE/docker-context" && -s "$KUBECONFIG" ]] ||
      fail "Ya existe $CLUSTER sin estado de este laboratorio. No se modificara."
    require_lab
    printf 'Reutilizando %s; no se borran los ejercicios.\n' "$CLUSTER"
  else
    umask 077
    mkdir -p "$STATE"
    printf '%s\n' "$DOCKER_CONTEXT" > "$STATE/docker-context"
    # Nodes cannot be Ready until the external CNI is installed.
    kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" \
      --config "$ROOT/lab/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 0s
  fi
  require_lab
  chmod 600 "$KUBECONFIG"

  helm template calico-crds crd.projectcalico.org.v1 \
    --repo https://docs.tigera.io/calico/charts --version v3.32.2 |
    k apply --server-side -f -
  k wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
  h upgrade --install calico tigera-operator \
    --repo https://docs.tigera.io/calico/charts --version v3.32.2 \
    --namespace tigera-operator --create-namespace \
    -f "$ROOT/lab/calico-values.yaml" --wait --timeout 10m
  k wait --for=create daemonset/calico-node -n calico-system --timeout=300s
  k rollout status daemonset/calico-node -n calico-system --timeout=300s
  k wait --for=condition=Ready nodes --all --timeout=300s
  k rollout status deployment/coredns -n kube-system --timeout=180s
  k rollout status deployment/local-path-provisioner -n local-path-storage --timeout=180s

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
  printf '\nLaboratorio listo. Entrar: bash scripts/lab.sh shell\n'
  k get nodes
}

down() {
  [[ "${1:-}" == --yes && $# -eq 1 ]] || fail "Borrado requiere: bash scripts/lab.sh down --yes"
  need kind
  require_lab
  docker_ready
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
  rm -f "$STATE/kubeconfig" "$STATE/docker-context"
  printf 'Cluster borrado. Se conservan respuestas e historial en .lab/.\n'
}

command="${1:-help}"
[[ $# -eq 0 ]] || shift
case "$command" in
  help|-h|--help) usage ;;
  doctor|up|status|check|shell)
    [[ $# -eq 0 ]] || fail "$command no acepta argumentos."
    case "$command" in
      doctor) doctor ;;
      up) up ;;
      status) status ;;
      check)
        require_lab
        export CKA_LAB_ROOT="$ROOT"
        bash "$ROOT/scripts/check-lab.sh"
        ;;
      shell)
        require_lab
        export CKA_LAB_ROOT="$ROOT"
        exec bash --noprofile --rcfile "$ROOT/lab/bashrc" -i
        ;;
    esac
    ;;
  kubectl|helm)
    require_lab
    if [[ "$command" == kubectl ]]; then k "$@"; else need helm; h "$@"; fi
    ;;
  node)
    [[ $# -eq 1 ]] || fail "Indica exactamente un nodo: cp, w1 o w2."
    case "$1" in
      cp) node="$CLUSTER-control-plane" ;;
      w1) node="$CLUSTER-worker" ;;
      w2) node="$CLUSTER-worker2" ;;
      *) fail "Nodo no permitido: $1. Usa cp, w1 o w2." ;;
    esac
    require_lab
    docker_ready
    [[ "$(docker inspect --format '{{index .Config.Labels "io.x-k8s.kind.cluster"}}' "$node")" == "$CLUSTER" ]] ||
      fail "El contenedor no pertenece al laboratorio."
    exec docker exec -it "$node" bash
    ;;
  down) down "$@" ;;
  *) usage >&2; fail "Comando desconocido: $command" ;;
esac
