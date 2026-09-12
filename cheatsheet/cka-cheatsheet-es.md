# CKA — Chuleta práctica en español

**Referencia para preparar Kubernetes 1.35 · revisada el 13/09/2026.**

Basada en los ejercicios, la chuleta y los procedimientos de diagnóstico del repositorio, contrastando los puntos conflictivos con documentación oficial. **Para estudiar y practicar: no es material autorizado para consultar durante el examen.** Allí usa exclusivamente los [recursos permitidos por Linux Foundation](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed).

**Regla de oro:** host correcto → contexto/namespace → cambio mínimo → verificar el requisito → guardar donde se pide → salir del host.

| Troubleshooting | Arquitectura / instalación | Redes | Workloads / scheduling | Storage |
|---|---|---|---|---|
| **30 %** | **25 %** | **20 %** | **15 %** | **10 %** |

**Saltos:** [Inicio](#1-inicio-y-contexto) · [YAML](#2-generar-y-modificar-yaml) · [Diagnóstico](#3-diagnosticar-antes-de-cambiar) · [Workloads](#4-workloads-configuración-y-hpa) · [RBAC](#5-rbac-mínimo-privilegio) · [Nodos](#6-scheduling-y-mantenimiento) · [Redes](#7-services-y-dns) · [NetworkPolicy](#8-networkpolicy) · [Gateway](#9-ingress-y-gateway-api) · [Storage](#10-storage) · [Helm](#11-helm-kustomize-y-operadores) · [Control plane](#12-nodos-linux-y-static-pods) · [kubeadm](#13-kubeadm-instalación-y-upgrade) · [etcd](#14-etcd-backup-y-restauración) · [Cierre](#15-últimos-minutos).

## 1. Inicio y contexto

Lee primero el **host asignado**. En el entorno actual las tareas se resuelven en hosts a los que entras por SSH; no basta con cambiar de contexto en el host base.

```bash
ssh nombre-del-host
# En ese host, solo si no están configurados:
alias k=kubectl
export do='--dry-run=client -o yaml'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

k config current-context
k config get-contexts
# Solo si el enunciado pide un contexto concreto:
k config use-context nombre-del-contexto

NS=namespace-del-enunciado
k config set-context --current --namespace="$NS"
k get ns "$NS"
```

En los ejemplos, **define** `$POD`, `$DEP`, `$CONTAINER`, `$SVC`, `$NODE` y `$SA` con los nombres reales; no son valores mágicos. Usa la imagen, versión, puerto y ruta del enunciado, no los de ejemplo.

**Vim:** `:set et ts=2 sw=2 ai number` · `i` insertar · `Esc` modo normal · `:wq` guardar/salir · `:q!` descartar · `/texto` buscar · `u` deshacer · `gg`/`G` inicio/final. Al pegar, `:set paste`, pegar en inserción y luego `:set nopaste`.

**Escritorio Linux:** copiar/pegar en terminal con `Ctrl+Shift+C/V`; evita `Ctrl+W`, que puede cerrar una pestaña; las instrucciones PSI indican `Ctrl+Alt+W` como alternativa.

## 2. Generar y modificar YAML

**Generar → editar → validar → aplicar → comprobar.** No escribas a mano lo que genera `kubectl`.

```bash
k -n "$NS" run web --image=nginx:1.28 $do > pod.yaml
k -n "$NS" create deployment web --image=nginx:1.28 --replicas=2 $do > deploy.yaml
# Requiere que el Deployment web ya exista:
k -n "$NS" expose deployment web --port=80 --target-port=80 $do > svc.yaml
k -n "$NS" create job once --image=busybox:1.37.0 $do -- sh -c 'date' > job.yaml
k -n "$NS" create cronjob periodic --image=busybox:1.37.0 \
  --schedule='*/5 * * * *' $do -- date > cronjob.yaml

k explain deployment.spec.template.spec.containers
k explain deployment.spec.strategy.rollingUpdate
k explain pvc.spec
k -n "$NS" apply --dry-run=server -f deploy.yaml
k -n "$NS" apply -f deploy.yaml
k -n "$NS" rollout status deployment/web --timeout=120s
```

`$do` se expande en varios argumentos en **Bash**. El dry-run de servidor valida admisión/esquema, **no** descarga imágenes, agenda Pods ni prueba la aplicación.

Para cambios existentes, prefiere `set image`, `set resources`, `set env` o un parche pequeño:

```bash
k -n "$NS" set image deployment/"$DEP" "$CONTAINER=imagen:version"
k -n "$NS" patch deployment "$DEP" --type=merge \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.priorityClassName}{"\n"}'
```

**Ojo con arrays:** JSON Merge Patch reemplaza listas completas; no lo uses despreocupadamente sobre `containers`. Un cambio en la plantilla de un Deployment crea Pods nuevos. Muchos campos de un Pod existente son inmutables: cambia su controlador o recrea el Pod solo cuando proceda.

## 3. Diagnosticar antes de cambiar

Empieza por el alcance del síntoma: **un Pod → aplicación; todos los Pods de un nodo → nodo; todo el cluster → control plane/red**. No reinicies componentes al azar.

```bash
k -n "$NS" get pods -o wide
k -n "$NS" describe pod "$POD"
k -n "$NS" get events --sort-by=.metadata.creationTimestamp
k -n "$NS" logs "$POD" -c "$CONTAINER" --tail=80
k -n "$NS" logs "$POD" -c "$CONTAINER" --previous --tail=80
k -n "$NS" exec "$POD" -c "$CONTAINER" -- printenv MODE
k top nodes
k -n "$NS" top pods --containers
```

| Síntoma | Mira primero | Verifica tras corregir |
|---|---|---|
| `Pending` | Events: requests, taints, affinity, PVC, cuotas | Pod asignado al nodo esperado y Ready |
| `ImagePullBackOff` | Imagen/tag, registro, credenciales, red del nodo | Imagen correcta y contenedor arrancado |
| `CrashLoopBackOff` | `logs --previous`, Last State, comando, configuración, probes | Reinicios estables y aplicación responde |
| `OOMKilled` | Reason, límite de memoria, consumo real | Memoria suficiente sin incumplir el enunciado |
| Service sin tráfico | Selector → Pods Ready → EndpointSlices → targetPort | Petición desde otro Pod |
| DNS falla | `resolv.conf`, CoreDNS, Service DNS, egress UDP/TCP 53 | Nombre y conexión resuelven desde el cliente |
| `Forbidden` | Identidad, verbo, recurso/subrecurso y namespace | Prueba positiva y negativa con `auth can-i` |
| `NotReady` | Conditions, kubelet, runtime, CNI, disco | Nodo Ready; workloads recuperados |
| API no responde | Host/contexto, endpoint/TLS/red; después runtime y static Pods | API `/readyz` y componentes sanos |

**137 significa SIGKILL, no demuestra por sí solo OOM.** Confirma `reason: OOMKilled`. `Running` tampoco implica `Ready` ni que el Service funcione.

Si la imagen no tiene herramientas:

```bash
k -n "$NS" debug -it "$POD" --image=busybox:1.37.0 --target="$CONTAINER"
```

Un contenedor efímero de depuración no desaparece del objeto Pod al salir. `--target` depende del soporte del runtime para compartir el espacio de procesos.

## 4. Workloads, configuración y HPA

```bash
k -n "$NS" rollout status deployment/"$DEP" --timeout=120s
k -n "$NS" rollout history deployment/"$DEP"
k -n "$NS" rollout undo deployment/"$DEP"                 # Solo si se pide rollback
k -n "$NS" scale deployment/"$DEP" --replicas=3
k -n "$NS" get deploy "$DEP" -o wide

k -n "$NS" create configmap app-config --from-literal=MODE=prod
k -n "$NS" create secret generic app-secret --from-file=password=./password.txt
k -n "$NS" set env deployment/"$DEP" --from=configmap/app-config
k -n "$NS" set env deployment/"$DEP" --from=secret/app-secret

k -n "$NS" set resources deployment/"$DEP" -c "$CONTAINER" \
  --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=128Mi
k -n "$NS" autoscale deployment "$DEP" --min=1 --max=5 --cpu-percent=50
k -n "$NS" describe hpa "$DEP"
k -n "$NS" get hpa "$DEP" -w
```

No imprimas ni compartas secretos reales. ConfigMap/Secret por **variables de entorno** requieren Pods nuevos para recoger cambios; volúmenes proyectados se actualizan eventualmente, pero montajes `subPath` no reciben esas actualizaciones.

| Concepto | Recordatorio |
|---|---|
| `requests` / `limits` | Scheduler usa requests; límites restringen uso. `100m` = 0,1 CPU; `128Mi` es memoria |
| Readiness | Controla disponibilidad para tráfico; no reinicia el contenedor |
| Liveness | Fallos repetidos provocan reinicio del contenedor |
| Startup | Hasta tener éxito, protege el arranque retrasando readiness/liveness |
| HPA `Utilization` | Porcentaje sobre **requests**, no sobre limits; necesita métricas y requests de los contenedores relevantes |
| HPA `AverageValue` | **Sí admite CPU/memoria absolutas**, por ejemplo `averageValue: 100m`; no es lo mismo que 50 % |
| HPA `<unknown>` | Revisar métricas, requests, Ready y `scaleTargetRef`; no atribuirlo automáticamente a una sola causa |
| StatefulSet | Identidad/PVC estables; comprueba Service gobernante, orden y persistencia |
| DaemonSet | Pods por nodo elegible; no se escala mediante `replicas` |
| Sidecar nativo | En `initContainers`, con `restartPolicy: Always`; no confundir con un init que debe finalizar |

No combines cambios manuales continuos de `replicas` con un HPA. La reducción de réplicas tiene estabilización; no exijas que sea inmediata.

## 5. RBAC: mínimo privilegio

```bash
k -n "$NS" create serviceaccount "$SA"
k -n "$NS" create role pod-reader --verb=get,list,watch --resource=pods
k -n "$NS" create rolebinding pod-reader --role=pod-reader --serviceaccount="$NS:$SA"

k auth can-i list pods -n "$NS" --as="system:serviceaccount:$NS:$SA"
k auth can-i delete pods -n "$NS" --as="system:serviceaccount:$NS:$SA"
k auth can-i get pods --subresource=log -n "$NS" --as="system:serviceaccount:$NS:$SA"
```

Resultado esperado del ejemplo: **yes / no / no** si no existen otros permisos.

**Role** y **RoleBinding**: namespace. **ClusterRole**: definición reutilizable y recursos globales. Un RoleBinding puede referenciar un ClusterRole y limitar sus permisos namespaced al namespace del binding; un ClusterRoleBinding los concede a nivel cluster.

`pods` ≠ `pods/log` ≠ `pods/exec`. No otorgues `cluster-admin` para solucionar un `Forbidden`; concede solo el verbo/recurso solicitado. `roleRef` es inmutable: si debe cambiar, hay que reemplazar el binding deliberadamente.

## 6. Scheduling y mantenimiento

```bash
k get nodes --show-labels
k describe node "$NODE"
k get node "$NODE" -o jsonpath='{.spec.taints}{"\n"}'
k label node "$NODE" disk=ssd
k taint node "$NODE" dedicated=training:NoSchedule
k taint node "$NODE" dedicated=training:NoSchedule-   # Solo quitar esta taint si procede
k create priorityclass high-priority --value=1000 --description='Practice priority'

k cordon "$NODE"
k get pdb -A
k drain "$NODE" --ignore-daemonsets --timeout=120s
# Tras mantenimiento y comprobaciones:
k uncordon "$NODE"
k get nodes
```

`cordon` impide scheduling nuevo, pero no expulsa Pods existentes. `drain` evacua y respeta PDB; no evacua los DaemonSets ni los mirror Pods.

**No añadas `--force`, `--disable-eviction` o `--delete-emptydir-data` por costumbre.** Esta última opción permite perder datos de `emptyDir`; resuelve primero la razón del bloqueo. `--force` en drain no es una solución para saltarse PDB.

`nodeSelector`/affinity atraen o exigen nodos; una toleration **permite**, no obliga a ir al nodo. `NoSchedule` no expulsa existentes; `NoExecute` puede hacerlo. Evita `nodeName` cuando dependes del scheduler, especialmente con `WaitForFirstConsumer`.

## 7. Services y DNS

**Cadena de diagnóstico:** selector → readiness → EndpointSlices → puerto real → DNS → NetworkPolicy/CNI.

```bash
k -n "$NS" get service "$SVC" -o yaml
k -n "$NS" get pods --show-labels
k -n "$NS" get endpointslices -l "kubernetes.io/service-name=$SVC" -o yaml
k -n "$NS" exec "$POD" -- cat /etc/resolv.conf
k -n "$NS" run dns-check --image=busybox:1.37.0 --restart=Never --rm -i \
  -- nslookup kubernetes.default.svc.cluster.local
k -n "$NS" exec "$POD" -- wget -T 3 -qO- "http://$SVC.$NS.svc.cluster.local:80"

k -n kube-system get pods -l k8s-app=kube-dns
k -n kube-system logs deployment/coredns --tail=50
k -n kube-system get configmap coredns -o yaml
```

`port` = Service; `targetPort` = puerto donde realmente escucha el proceso; `containerPort` **no abre puertos**. `NodePort` usa por defecto 30000–32767; `LoadBalancer` necesita una implementación de balanceador.

Usa EndpointSlices (`discovery.k8s.io/v1`) en lugar de depender del recurso Endpoints antiguo. Un Service con selector apunta a Pods **de su mismo namespace**; inspecciona las condiciones `ready` de los endpoints.

## 8. NetworkPolicy

**El CNI debe implementarla.** Selecciona Pods del namespace de la política y aísla **solo la dirección indicada** (`Ingress`, `Egress` o ambas). Las reglas de políticas aplicables se **suman**; no existe orden «primera regla gana».

Para permitir una conexión, deben permitirla el **egress del origen** y el **ingress del destino**, si están aislados. Las respuestas de una conexión permitida se permiten implícitamente.

Ejemplo: seleccionar `app: api` y permitir TCP/80 solo desde Pods `role: frontend` del namespace `clients`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-from-frontend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: clients
          podSelector:
            matchLabels:
              role: frontend
      ports:
        - protocol: TCP
          port: 80
```

**Mismo elemento de `from`: AND. Elementos separados por `-`: OR.** Un `podSelector` sin `namespaceSelector` selecciona Pods del namespace de la política.

Fragmento de `spec` para permitir **solo DNS a CoreDNS** como egress; combina con las demás salidas exigidas:

```yaml
podSelector: {}
policyTypes: [Egress]
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
```

Comprueba labels y el DNS real de ese cluster; NodeLocal DNS puede requerir otra regla. `ingress: []` niega ingreso; `ingress: [{}]` permite todo el ingreso a los Pods seleccionados, sin quitar posibles restricciones de salida del origen.

**Verificar:** `k -n "$NS" describe netpol` y probar un cliente autorizado **y otro no autorizado**. Un timeout por DNS roto no demuestra que la política sea correcta.

## 9. Ingress y Gateway API

```bash
k get ingressclass,gatewayclass
k -n "$NS" create ingress web --class=traefik \
  --rule='app.cka.test/*=web:80' $do > ingress.yaml
k -n "$NS" apply -f ingress.yaml
k -n "$NS" describe ingress web
k -n "$NS" get gateway,httproute
k -n "$NS" get gateway web -o yaml
k -n "$NS" get httproute web -o yaml
```

**La clase del ejemplo es la del laboratorio; en el examen usa la existente o solicitada.** Un objeto Ingress o Gateway no instala su controlador.

| Recurso | Campos que deben encajar | Evidencia |
|---|---|---|
| GatewayClass | `controllerName` del controlador | `Accepted=True` |
| Gateway | `gatewayClassName`, listener, puerto, protocolo, `allowedRoutes` | `Accepted=True`, `Programmed=True`, listener válido |
| HTTPRoute | `parentRefs`, hostname, matches, `backendRefs.name/port` | Condiciones del parent: `Accepted=True` y `ResolvedRefs=True` |
| Ingress | `ingressClassName`, host/path, Service/puerto, TLS si se pide | Respuesta HTTP con Host correcto |

`backendRefs.port` es el puerto **del Service**, no necesariamente `targetPort`. Un backend en otro namespace requiere autorización mediante `ReferenceGrant` en el namespace del backend. Una ruta en otro namespace que su Gateway depende también de `allowedRoutes`.

Plantilla completa: [Gateway + HTTPRoute](../skeletons/gateway-api.yaml). La comprobación decisiva es una petición HTTP; el estado del objeto no sustituye la prueba del tráfico.

## 10. Storage

```bash
k get storageclass,pv
k -n "$NS" get pvc
k -n "$NS" describe pvc nombre-del-claim
k -n "$NS" describe pod "$POD"
k get pv nombre-del-pv -o yaml
```

| Campo / concepto | Lo que no debes olvidar |
|---|---|
| PV / PVC | PV global; PVC namespaced; el Pod usa un claim de su namespace |
| Binding | Capacidad, accessModes, storageClassName, volumeMode, selector/prebinding y topology deben encajar |
| `storageClassName: ""` | Solicita explícitamente sin clase; omitirlo puede usar la clase por defecto |
| `WaitForFirstConsumer` | PVC Pending puede ser normal hasta que haya consumidor y decisión del scheduler |
| RWO | Escritura desde **un nodo**, no necesariamente un solo Pod |
| RWOP | Escritura desde **un Pod**; requiere soporte CSI |
| `Retain` / `Delete` | Conservar almacenamiento para recuperación manual / eliminarlo al reclamar, según el provisionador |
| Expansión | Requiere StorageClass y driver compatibles; no se reduce capacidad con un resize |

Pod: `spec.volumes[].persistentVolumeClaim.claimName` + `containers[].volumeMounts[].name/mountPath`.

**Prueba real:** escribir un marcador, recrear únicamente el Pod consumidor cuando corresponda y leerlo otra vez. **No borres el PVC** para verificar persistencia. El driver puede necesitar componentes CSI sanos y permisos en el nodo.

## 11. Helm, Kustomize y operadores

```bash
helm list -A
helm show values repo/chart --version VERSION
helm template release repo/chart --version VERSION -n "$NS" -f values.yaml
helm upgrade --install release repo/chart --version VERSION \
  -n "$NS" --create-namespace -f values.yaml --wait --timeout 3m
helm status release -n "$NS"
helm history release -n "$NS"
helm rollback release REVISION -n "$NS" --wait --timeout 3m

k kustomize overlays/prod
k -n "$NS" apply --dry-run=server -k overlays/prod
k -n "$NS" apply -k overlays/prod
k get crd
k api-resources
```

`repo/chart`, `VERSION`, `release` y `REVISION` son marcadores. Añade el repositorio/URL o usa OCI según la tarea; no uses `latest` por inercia. **Inspecciona valores y YAML renderizado:** una clave de values puede cambiar entre versiones del chart.

Con Kustomize cambia la base o el overlay adecuado y comprueba el resultado; no edites solo una copia renderizada que luego quedará desactualizada.

**CRD** define el tipo; **CR** es una instancia; **operador** reconcilia su estado. Si el tipo no existe, revisa CRD establecida, versión servida y controlador antes de crear más recursos.

## 12. Nodos Linux y static Pods

En el **nodo afectado**, no en macOS ni en el host base del examen:

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet -n 80 --no-pager
sudo journalctl -u containerd -n 50 --no-pager
sudo crictl info
sudo crictl ps -a
sudo crictl logs ID_DEL_CONTENEDOR
sudo grep staticPodPath /var/lib/kubelet/config.yaml
sudo ls -l /etc/kubernetes/manifests
df -h
df -i
sudo ss -lntp
sudo kubeadm certs check-expiration
```

`containerd` es habitual, pero usa el runtime real. Si `crictl` no conecta, revisa su endpoint en `/etc/crictl.yaml` y el socket del runtime. Renovar certificados o reiniciar CoreDNS no son soluciones universales: primero identifica la causa.

Un static Pod lo gestiona **kubelet desde un archivo**. Borrar su mirror Pod con `kubectl` no elimina la carga. Guarda copias fuera de `staticPodPath`; incluso archivos de respaldo pueden ser interpretados como manifiestos.

Antes de editar un manifiesto del control plane, guarda una copia en una ruta segura, por ejemplo `/root/cka-backups/`, con nombre único. Comprueba YAML, rutas montadas, puertos, certificados y flags. Si la API está caída, **`crictl` y `journalctl` siguen siendo útiles**.

Después de reparar la causa, si se requiere:

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet
# Desde un host con credenciales kubectl adecuadas:
k get --raw='/readyz'
k get nodes
k -n kube-system get pods -o wide
```

## 13. kubeadm: instalación y upgrade

**Solo VMs Linux / entorno asignado. No hagas upgrades por apt dentro de kind.**

Instalación: preparar runtime/CRI y cgroups, red/sysctl, swap según configuración soportada, paquetes/versiones → `kubeadm init --config cluster.yaml` en el control plane → configurar kubeconfig → instalar el CNI apropiado → `kubeadm join ...` en workers → verificar nodos y DNS. No instales un segundo CNI sobre uno existente. Los tokens de join son credenciales.

**HA:** endpoint estable/balanceador para la API, varios control planes y quorum etcd; no basta con poner réplicas a kube-apiserver. Para etcd, una mayoría debe estar disponible: tres miembros toleran uno caído.

Upgrade: **primer control plane → restantes control planes → workers**, secuencialmente. No saltes versiones minor. Respalda antes; revisa compatibilidad del CNI y el repositorio `pkgs.k8s.io` de la minor destino.

Consulta paquetes y define `TARGET` como versión Kubernetes (`v1.35.x`, sustituyendo x) y `PKG` como versión exacta del paquete que exige la tarea:

```bash
sudo apt-get update
apt-cache madison kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get install -y "kubeadm=$PKG"
sudo apt-mark hold kubeadm
kubeadm version
```

| Dónde | Paso kubeadm después de actualizar su paquete |
|---|---|
| Primer control plane | `sudo kubeadm upgrade plan` → `sudo kubeadm upgrade apply "$TARGET"` |
| Control planes adicionales | `sudo kubeadm upgrade node` |
| Worker | Drenarlo desde un host con kubectl; en el worker, `sudo kubeadm upgrade node` |

**En cada nodo, drenar antes de actualizar kubelet**, incluido el control plane. No confundas la actualización del plano de control con la del kubelet.

```bash
# En un host con acceso administrativo al cluster:
k drain "$NODE" --ignore-daemonsets --timeout=120s

# En el nodo que estás actualizando:
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y "kubelet=$PKG" "kubectl=$PKG"
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet

# De nuevo en el host con kubectl:
k uncordon "$NODE"
k get nodes -o wide
```

Comprueba la versión de **todos** los nodos y que no quede ninguno `SchedulingDisabled`. Usa el [procedimiento oficial de la versión destino](https://v1-35.docs.kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/), no versiones fijas copiadas de un ejercicio.

## 14. etcd: backup y restauración

**Descubre endpoint y certificados; no adivines rutas.** Ejemplo kubeadm con etcd local, ejecutado en su control plane:

```bash
sudo grep -E 'listen-client-urls|advertise-client-urls|cert|key|data-dir|name=' \
  /etc/kubernetes/manifests/etcd.yaml

# Adapta estas rutas al nodo y guarda el archivo donde indique la tarea:
SNAPSHOT=/tmp/etcd-backup.db
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save "$SNAPSHOT"
sudo etcdutl snapshot status "$SNAPSHOT" -w table
```

**etcd 3.6:** `etcdctl` guarda snapshots; **`etcdutl`** inspecciona/restaura. No uses la vieja combinación `etcdctl snapshot restore/status --write-table`.

**Restaurar es destructivo para el estado posterior al backup: solo si se solicita.** Para un único miembro, define `RESTORE_DIR` como directorio nuevo, y `ETCD_MEMBER`/`PEER_URL` según la configuración que tendrá el miembro restaurado:

```bash
sudo etcdutl snapshot restore "$SNAPSHOT" \
  --data-dir="$RESTORE_DIR" \
  --name="$ETCD_MEMBER" \
  --initial-cluster="$ETCD_MEMBER=$PEER_URL" \
  --initial-advertise-peer-urls="$PEER_URL" \
  --bump-revision=1000000000 --mark-compacted
```

El bump es el ejemplo recomendado por etcd para evitar que las revisiones retrocedan en clientes Kubernetes; adáptalo al escenario y confirma soporte con `etcdutl snapshot restore --help`. Restore trabaja sobre el archivo, no necesita conectarse al endpoint TLS.

**Secuencia:** guardar manifiesto original fuera de su carpeta → detener el static Pod retirando su manifiesto y confirmar con `crictl` → restaurar al directorio nuevo → ajustar montaje/manifiesto y reponerlo → comprobar salud etcd, API, nodos y objetos restaurados. Conserva los datos originales para recuperación.

**Ruta host ≠ ruta del contenedor.** Si cambias `volumes[].hostPath.path` al directorio restaurado, puedes conservar `volumeMounts[].mountPath` y `--data-dir` internos si siguen apuntando al montaje correcto. No cambies los tres a ciegas.

Comprueba la salud después, adaptando nuevamente endpoint/certificados:

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
k get --raw='/readyz'
k get nodes
```

En multi-miembro se requiere restaurar una membresía coherente desde el mismo snapshot; **no apliques esta receta de un único miembro a un cluster HA**. Consulta la [recuperación oficial de etcd](https://etcd.io/docs/v3.6/op-guide/recovery/).

## 15. Últimos minutos

| Antes de dar una tarea por terminada | Evidencia mínima |
|---|---|
| Host, contexto, namespace, nombre y ruta correctos | Releer exactamente el enunciado |
| Objeto creado/modificado | `get`/`describe`; no solo el mensaje de `apply` |
| Deployment / Pod | Rollout completado, réplicas y Ready; imagen y configuración correctas |
| Service / Gateway / Ingress | Tráfico real desde el lugar apropiado |
| RBAC / NetworkPolicy | Caso permitido **y** caso denegado |
| PVC | Bound y datos accesibles/persistentes según requisito |
| HPA | Target correcto, métricas disponibles; si se pide escalar, probarlo |
| Mantenimiento | Nodos Ready, versiones correctas y uncordon |
| Entrega | Archivo en la ruta solicitada, comandos sin error; salir con `exit` al host base |

Dos pasadas: tareas claras primero; si te atascas 6–8 minutos sin avanzar, marca y cambia. Reserva **15–20 minutos** para verificar. No cierres una tarea con la promesa de que «debería funcionar».

**Evita los atajos peligrosos:** borrar Pods con `--force --grace-period=0` por rutina, eliminar PVC, cambiar permisos globales, desactivar TLS o reiniciar servicios sin diagnóstico.

## Aplicación a nuestro laboratorio

```bash
bash scripts/lab.sh shell
# Clases disponibles: traefik (Ingress y Gateway), standard (StorageClass)
# Tres nodos: cka-10days-control-plane, cka-10days-worker, cka-10days-worker2
```

Para comandos Linux entra con `bash scripts/lab.sh node cp`, `w1` o `w2`; en el examen sigue el host SSH que indique la tarea. El `--kubelet-insecure-tls` usado por Metrics Server en kind **no es una recomendación de producción**.

**Lecturas de apoyo:** [ruta de 10 días](../lab/README.md) · [ejercicios](../exercises/README.md) · [plantillas YAML](../TEMPLATES.md) · [playbook original](../troubleshooting/README.md).

**Fuentes de contraste:** [temario CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) · [instrucciones del examen](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) · [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) · [HPA 1.35](https://v1-35.docs.kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/) · [upgrade kubeadm 1.35](https://v1-35.docs.kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) · [etcd 3.6](https://etcd.io/docs/v3.6/op-guide/recovery/).
