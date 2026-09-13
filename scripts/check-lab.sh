#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="cka-check-$(date +%s)-$$"
case "${CKA_LAB_BACKEND:-kind}" in
  kind) LAB_CLI="$ROOT/scripts/lab.sh"; WORKER1=cka-10days-worker; WORKER2=cka-10days-worker2 ;;
  vms) LAB_CLI="$ROOT/scripts/vm-lab.sh"; WORKER1=node01; WORKER2=node02 ;;
  *) printf 'ERROR: backend desconocido.\n' >&2; exit 1 ;;
esac
k() { bash "$LAB_CLI" kubectl "$@"; }
kn() { k -n "$NS" "$@"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then
    printf '\nDiagnostico de la comprobacion fallida:\n' >&2
    kn get pods,pvc,networkpolicy,gateway,httproute,ingress -o wide ||
      printf 'No se pudo obtener el estado de los recursos.\n' >&2
    kn get events --sort-by=.lastTimestamp ||
      printf 'No se pudieron obtener los eventos.\n' >&2
  fi
  if ! k delete namespace "$NS" --wait=true --timeout=120s; then
    printf 'No se pudo limpiar %s. Eliminalo cuando se recupere la API.\n' "$NS" >&2
    result=1
  fi
  exit "$result"
}

fetch() {
  kn exec "$1" -- wget -T 3 -qO- "http://web.$NS.svc.cluster.local"
}

printf 'Comprobando laboratorio; namespace temporal: %s\n' "$NS"
k wait --for=condition=Ready node --all --timeout=120s
[[ "$(k get nodes -o name | wc -l | tr -d ' ')" == 3 ]] || fail "Se esperaban tres nodos."
[[ "$(k -n traefik get service traefik -o jsonpath='{.spec.type}')" == ClusterIP ]] ||
  fail "Traefik debe usar un Service ClusterIP en este laboratorio."
k create namespace "$NS"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -e "s/cka-10days-worker2/$WORKER2/g" -e "s/cka-10days-worker/$WORKER1/g" \
  "$ROOT/lab/check/workloads.yaml" | kn apply -f -
kn rollout status deployment/web --timeout=300s
kn wait --for=condition=Ready pod/allowed pod/denied --timeout=180s
kn wait --for=jsonpath='{.status.phase}'=Bound pvc/web-data --timeout=60s
kn exec allowed -- nslookup "web.$NS.svc.cluster.local"
[[ "$(fetch allowed)" == CKA-lab-ok ]] || fail "Fallo HTTP entre nodos o lectura del PVC."
[[ "$(fetch denied)" == CKA-lab-ok ]] || fail "El cliente negativo no tiene conectividad de base."
printf 'OK: DNS, Service y HTTP entre workers; PVC provisionado y legible.\n'

kn apply -f "$ROOT/lab/check/policy.yaml"
blocked=false
for ((attempt=0; attempt<15; attempt++)); do
  # Only a real network timeout counts; exec/API/DNS errors are not a pass.
  result=0
  kn exec denied -- sh -c '
    output=$(wget -T 2 -qO- "$1" 2>&1)
    status=$?
    [ "$status" -ne 0 ] || exit 0
    printf "%s\n" "$output" >&2
    case "$output" in
      *"timed out"*) exit 42 ;;
      *) exit 43 ;;
    esac
  ' sh "http://web.$NS.svc.cluster.local" || result=$?
  if [[ "$result" == 42 ]]; then blocked=true; break; fi
  [[ "$result" == 0 ]] || fail "La prueba negativa fallo por una causa distinta de bloqueo de red."
  sleep 2
done
[[ "$blocked" == true ]] || fail "NetworkPolicy no bloquea al cliente no autorizado."
[[ "$(fetch allowed)" == CKA-lab-ok ]] || fail "NetworkPolicy bloquea tambien al cliente autorizado."
kn exec denied -- nslookup "web.$NS.svc.cluster.local"
printf 'OK: NetworkPolicy permite al cliente autorizado y bloquea al otro.\n'

kn apply -f "$ROOT/lab/check/routes.yaml"
kn wait --for=condition=Programmed gateway/web --timeout=120s
kn wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
  httproute/web --timeout=120s
kn wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'=True \
  httproute/web --timeout=120s
for host in gateway.cka.test ingress.cka.test; do
  routed=false
  for ((attempt=0; attempt<20; attempt++)); do
    if response="$(kn exec allowed -- wget -T 3 -qO- --header="Host: $host" \
      http://traefik.traefik.svc.cluster.local)" && [[ "$response" == CKA-lab-ok ]]; then
      routed=true
      break
    fi
    sleep 2
  done
  [[ "$routed" == true ]] || fail "No funciona la ruta HTTP para $host."
done
printf 'OK: Gateway/HTTPRoute e Ingress sirven trafico real.\n'

kn autoscale deployment web --min=1 --max=2 --cpu-percent=50
kn wait --for=condition=ScalingActive hpa/web --timeout=180s
metrics="$(k top nodes --no-headers)"
printf '%s\n' "$metrics"
[[ "$(printf '%s\n' "$metrics" | wc -l | tr -d ' ')" == 3 ]] || fail "Faltan metricas de nodos."
printf 'OK: metricas de los tres nodos y HPA con metricas disponibles.\n'
printf '\nTodas las comprobaciones han pasado; se limpiaran solo los recursos temporales.\n'
