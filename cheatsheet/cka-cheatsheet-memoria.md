# CKA — Chuleta de memoria revisada

**Kubernetes 1.34/1.35 · etcd 3.6 · 13/09/2026.** Revisión de la chuleta adjunta, conservando su enfoque de práctica rápida. Tapa el comando, escríbelo y comprueba; prioriza diagnóstico, kubeadm y etcd.

Para estudiar, **no para consultar durante el examen**. Usa allí únicamente los [recursos permitidos](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed). [Guía del estudiante](../lab/GUIA-ESTUDIANTE.md) · [Referencia extensa y YAML](cka-cheatsheet-es.md).

**Convención:** los ejemplos usan `web`, `dev`, `node01`; adáptalos al enunciado. `POD`, `CONTAINER`, `MEMBER`, `PEER` y demás variables requieren valores reales. No ejecutes todos los bloques como si fueran un script.

## 1. Calentamiento: Bash, no zsh

```bash
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
alias kn='kubectl config set-context --current --namespace'
export do='--dry-run=client -o yaml'
```

Vim: `:set et ts=2 sw=2 ai number` · `i` insertar · `Esc` salir de inserción · `:wq` guardar · `:q!` descartar · `/texto` buscar · `u` deshacer. `$do` se expande en varios argumentos en Bash.

No prepares el borrado forzado como atajo por defecto: `--force --grace-period=0` puede dejar procesos activos y no equivale a una terminación segura.

## 2. Reconocimiento: host → contexto → namespace

En el examen, lee el **host SSH asignado** y entra primero. Cambia de contexto solo cuando corresponda; no supongas que todas las tareas se hacen desde el host base.

```bash
hostname; whoami; pwd
k config current-context
k config get-contexts
# Si lo exige la tarea:
k config use-context nombre-del-contexto
kn dev
k get pods -n dev -o wide
k get pods -n dev --sort-by='.status.containerStatuses[0].restartCount'
k get events -n dev --sort-by=.metadata.creationTimestamp
k describe pod "$POD" -n dev
k explain deployment.spec.template.spec.containers
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

El orden de reinicios anterior mira el **primer contenedor**, no suma todos ni los init containers. `describe` completo antes de recortarlo: no pierdas Conditions, Last State ni eventos.

## 3. Crear, validar y aplicar

```bash
k create namespace dev
k -n dev run web --image=nginx:1.28 $do > pod.yaml
k -n dev create deployment web --image=nginx:1.28 --replicas=3 $do > deploy.yaml
k -n dev apply --dry-run=server -f deploy.yaml
k -n dev apply -f deploy.yaml
# expose necesita que el Deployment exista:
k -n dev expose deployment web --port=80 --target-port=80 $do > service.yaml
k -n dev apply -f service.yaml
k -n dev create service clusterip headless --clusterip=None --tcp=80:80 $do
k -n dev create configmap app --from-literal=MODE=practice
k -n dev create secret generic db --from-file=password=./password.txt
k -n dev create job once --image=busybox:1.37.0 -- date
k -n dev create cronjob tick --image=busybox:1.37.0 --schedule='*/5 * * * *' -- date
```

`password.txt` debe existir; usa datos ficticios y no imprimas ni publiques secretos. Un dry-run valida el objeto, **no** descarga la imagen ni prueba scheduling/tráfico. Para recursos sin generador imperativo, consulta YAML y `explain`.

## 4. Workloads, rollouts y HPA

```bash
k -n dev set image deployment/web nginx=nginx:1.28
k -n dev rollout status deployment/web --timeout=120s
k -n dev rollout history deployment/web
k -n dev rollout undo deployment/web --to-revision=2
k -n dev scale deployment/web --replicas=3
k -n dev rollout restart deployment/web
k -n dev set env deployment/web --from=configmap/app
k -n dev set resources deployment/web -c nginx \
  --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=128Mi
k -n dev autoscale deployment/web --min=2 --max=5 --cpu=70%
k -n dev describe hpa web
```

`nginx` es el **nombre del contenedor**, no necesariamente el del Deployment; inspecciónalo. No uses el antiguo `--record`. La revisión 2 debe existir antes de solicitar ese rollback.

**HPA:** necesita métricas; `70%` se calcula sobre requests, no limits. `--cpu=500m` expresa un objetivo absoluto, no un porcentaje. No mantengas `scale` manual compitiendo con un HPA. `--cpu-percent` sigue aceptándose en estos clientes, pero está deprecado.

**Probes:** readiness retira tráfico; liveness reinicia; startup protege el arranque. Scheduler usa requests; `100m` = 0,1 CPU. Un ConfigMap/Secret por variable de entorno requiere Pods nuevos para recoger cambios; `subPath` no se actualiza automáticamente.

## 5. Nodos y scheduling

```bash
k cordon node01
k get pdb -A
k drain node01 --ignore-daemonsets --timeout=120s
# Después del mantenimiento:
k uncordon node01
k taint node node01 dedicated=lab:NoSchedule
k taint node node01 dedicated=lab:NoSchedule-
k label node node01 disk=ssd
k top nodes
k -n dev top pods --sort-by=cpu
```

No añadas `--force` ni `--delete-emptydir-data` de forma automática: revisa el bloqueo y la pérdida de datos. `--force` en drain permite Pods sin controlador; **no** salta PDB. `cordon` no expulsa existentes.

`nodeSelector`/affinity seleccionan; tolerations **permiten**, no fuerzan un nodo. `NoSchedule` no expulsa; `NoExecute` sí puede hacerlo. Con `WaitForFirstConsumer`, evita `nodeName`, que omite el scheduler.

## 6. kubeadm: secuencia de upgrade

**Solo en Ubuntu.** Primero respaldo y salud del cluster. En cada nodo cambia el repositorio `pkgs.k8s.io` de v1.34 a v1.35. Ejemplo local: **1.34.11 → 1.35.8**; en el examen manda la versión solicitada.

```bash
# PRIMER CONTROL PLANE
sudo vim /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.35.8-1.1
sudo apt-mark hold kubeadm
kubeadm version -o short
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.8
k drain controlplane --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.8-1.1 kubectl=1.35.8-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
k uncordon controlplane
k get nodes
```

**Worker, uno cada vez:** drain desde el host con kubectl → SSH al worker → cambiar repositorio → actualizar y retener **kubeadm** → `sudo kubeadm upgrade node` → actualizar y retener **kubelet/kubectl** → daemon-reload/restart → uncordon desde el host con kubectl → Ready y versión.

No ejecutes `upgrade plan/apply` en workers ni instales kubelet antes de `upgrade node`. Control planes adicionales usan `upgrade node`. [Procedimiento local completo](../lab/vms/upgrade.md).

## 7. etcd: guardar con etcdctl, inspeccionar/restaurar con etcdutl

En el control plane, descubre nombre, peer URL, endpoint y rutas de certificados en el manifiesto. Los ejemplos TLS siguientes son los del lab kubeadm:

```bash
sudo grep -E 'name=|initial-cluster=|advertise-peer-urls|data-dir|cert-file|key-file' \
  /etc/kubernetes/manifests/etcd.yaml
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /opt/snap.db
sudo etcdutl snapshot status /opt/snap.db -w table
```

**Restore pierde los cambios posteriores al snapshot.** Para etcd de **un único miembro**: guardar manifiestos fuera de `staticPodPath` → detener el static Pod etcd retirando su manifiesto → confirmar la parada con `crictl` → restaurar a directorio nuevo:

```bash
# Valores de ESTE laboratorio; descubrirlos de nuevo en otro cluster
MEMBER=controlplane
PEER=https://192.168.57.10:2380
sudo etcdutl snapshot restore /opt/snap.db \
  --data-dir=/var/lib/etcd-restore \
  --name="$MEMBER" --initial-cluster="$MEMBER=$PEER" \
  --initial-advertise-peer-urls="$PEER" \
  --bump-revision=1000000000 --mark-compacted
```

Después, en el manifiesto guardado, cambiar **`volumes[].hostPath.path` de `etcd-data`** al directorio restaurado y reponer el manifiesto. Si el montaje interno sigue siendo `/var/lib/etcd`, conserva `mountPath` y `--data-dir` internos. No guardes copias en `/etc/kubernetes/manifests/`.

Confirma etcd `endpoint health` con los mismos parámetros TLS del backup; después API `/readyz`, nodos y objetos restaurados. El bump/compaction evita revisiones antiguas en clientes Kubernetes; no es una receta de restauración HA. [Detalle y precauciones](cka-cheatsheet-es.md#14-etcd-backup-y-restauración) · [recuperación oficial etcd 3.6](https://etcd.io/docs/v3.6/op-guide/recovery/).

## 8. Troubleshooting: del síntoma a la evidencia

| Síntoma | Primero | Causas frecuentes |
| --- | --- | --- |
| Pending | `describe pod` y PVC | Requests, taints/affinity, binding, cuotas |
| ImagePullBackOff | Events | Imagen/tag, credenciales, conectividad al registro |
| CrashLoopBackOff | Logs actuales/`--previous`, Last State | Comando, configuración, probes, memoria |
| CreateContainerConfigError | Events | ConfigMap/Secret o clave ausente |
| Nodo NotReady | Conditions, kubelet/runtime | CNI, cgroups, disco, certificados |
| API caída | Endpoint/red; después SSH y `crictl` | Static Pod, etcd, certificados o conectividad |
| Service sin tráfico | Selector → Ready → EndpointSlices | Selectores, destino no Ready, puerto, política |
| DNS roto | Cliente, CoreDNS, egress | `resolv.conf`, CoreDNS, UDP/TCP 53 |

```bash
k -n dev logs "$POD" -c "$CONTAINER" --tail=50
k -n dev logs "$POD" -c "$CONTAINER" --previous
k -n dev debug -it "$POD" --image=busybox:1.37.0 --target="$CONTAINER"
k get --raw='/readyz?verbose'
# EN EL NODO LINUX afectado:
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet -n 60 --no-pager
sudo crictl ps -a
sudo crictl logs ID_DEL_CONTENEDOR
df -h; df -i
sudo ss -lntp
sudo kubeadm certs check-expiration
```

Con la API caída, kubectl no administra el cluster: usa SSH, archivos y CRI. **Running ≠ Ready**; código 137 por sí solo no demuestra OOM. EndpointSlices vacíos no demuestran un puerto incorrecto: revisa primero selector y readiness.

`kubectl debug node/node01 -it --image=ubuntu:24.04` crea un **Pod de depuración**, no una sesión SSH. El nodo se monta en `/host`; no es privilegiado por defecto y depende de API/kubelet. `--profile=sysadmin` concede privilegios elevados solo si se necesitan y están autorizados. Elimina ese Pod por su nombre exacto al terminar.

## 9. Rutas de kubeadm que debes reconocer

| Qué | Ruta habitual |
| --- | --- |
| Static Pods | `/etc/kubernetes/manifests/`; confirmar `staticPodPath` en config del kubelet |
| Kubeconfigs | `/etc/kubernetes/*.conf`; **no** son archivos de flags |
| Configuración kubelet | `/var/lib/kubelet/config.yaml` |
| Flags kubeadm / overrides Ubuntu | `/var/lib/kubelet/kubeadm-flags.env` / `/etc/default/kubelet` |
| Certificados / datos etcd | `/etc/kubernetes/pki/` / `/var/lib/etcd` |
| Configuración / binarios CNI | `/etc/cni/net.d/` / `/opt/cni/bin/` |
| CRI containerd / cliente | `/run/containerd/containerd.sock` / `/etc/crictl.yaml` |
| Logs sin API | `journalctl -u kubelet`, `crictl logs`, `/var/log/containers/` |

Un static Pod lo gestiona kubelet; borrar su mirror Pod con kubectl no elimina la carga. Las rutas son habituales en kubeadm, no universales.

## 10. RBAC: crear y demostrar mínimo privilegio

```bash
k -n dev create serviceaccount deployer
k -n dev create role pod-reader --verb=get,list,watch --resource=pods
k -n dev create rolebinding pod-reader --role=pod-reader --serviceaccount=dev:deployer
k auth can-i get pods -n dev --as=system:serviceaccount:dev:deployer
k auth can-i delete pods -n dev --as=system:serviceaccount:dev:deployer
k auth can-i get pods --subresource=log -n dev --as=system:serviceaccount:dev:deployer
k auth can-i --list -n dev --as=system:serviceaccount:dev:deployer
```

Esperado: **yes / no / no**, si no hay otras concesiones. `pods`, `pods/log` y `pods/exec` son permisos diferentes.

Role/RoleBinding son namespaced. ClusterRole define permisos reutilizables, incluidos recursos globales; **no concede acceso por sí solo**. RoleBinding + ClusterRole concede permisos namespaced en ese namespace; no convierte permisos de nodos en namespaced. ClusterRoleBinding concede a nivel cluster. `roleRef` es inmutable.

## 11. Services, DNS y NetworkPolicy

```bash
k -n dev get service web -o yaml
k -n dev get pods --show-labels
k -n dev get endpointslices -l kubernetes.io/service-name=web -o yaml
k -n dev run dns-check --image=busybox:1.37.0 --restart=Never --rm -i \
  -- nslookup web.dev.svc.cluster.local
k -n dev get networkpolicy
k -n dev describe networkpolicy
```

DNS estable del Service: `servicio.namespace.svc.cluster.local` (el dominio puede variar). **No des por garantizado el DNS de un Pod basado en su IP**: depende de la implementación/configuración.

`port` = Service; `targetPort` = proceso destino; `containerPort` no abre puertos. NodePort predeterminado: 30000–32767. Un LoadBalancer necesita implementación.

**NetworkPolicy:** CNI que la aplique; ingress y egress se aíslan por separado; reglas se suman. Selectores en el mismo elemento de `from`/`to` = **AND**, elementos distintos = **OR**. Permitir egress DNS exige considerar **UDP y TCP 53** y el DNS real. Demuestra un cliente permitido y otro bloqueado; DNS roto no cuenta como bloqueo correcto.

## 12. Storage, Ingress y Gateway API

```bash
k get pv,storageclass
k -n dev get pvc
k -n dev describe pvc datos
k get ingressclass,gatewayclass
k -n dev get ingress,gateway,httproute
k -n dev describe gateway web
k -n dev get httproute web -o yaml
```

**Storage:** PV global, PVC del namespace del Pod. Binding: clase, capacidad, accessModes, volumeMode y topología. `WaitForFirstConsumer`: Pending puede ser normal hasta que el scheduler elija nodo. **RWO = un nodo**, no un único Pod; RWOP = un Pod, con CSI compatible. `Retain` conserva almacenamiento para recuperación manual; `Delete` puede borrar **también los datos**, según provisionador.

**Routing:** en este lab las clases son `traefik`; en el examen usa las solicitadas. GatewayClass Accepted; Gateway Programmed; HTTPRoute Accepted/ResolvedRefs; luego **HTTP real con Host correcto**. `backendRefs.port` es el puerto del Service. Backend entre namespaces: revisar `ReferenceGrant`; rutas entre namespaces: `allowedRoutes`.

## 13. Helm, Kustomize y CRDs

```bash
helm list -A
helm show values repo/chart --version VERSION
helm template release repo/chart --version VERSION -n dev -f values.yaml
helm upgrade --install release repo/chart --version VERSION -n dev \
  --create-namespace -f values.yaml --wait --timeout 3m
helm history release -n dev
helm rollback release REVISION -n dev --wait
k kustomize overlays/prod
k apply --dry-run=server -k overlays/prod
k apply -k overlays/prod
k get crd
k api-resources
```

`repo/chart`, `VERSION`, `release`, `REVISION` y las rutas son marcadores: configurar el repo/OCI indicado. **CRD define el tipo; CR es instancia; operador reconcilia.** Renderiza antes de aplicar.

## 14. Cierre y uso en nuestro laboratorio

**Terminado = requisito demostrado**, no solo exit code 0: namespace/nombre correctos, Ready, tráfico, permisos positivos/negativos, datos persistentes cuando se pide, nodos sin cordon y archivos en su ruta. Sal del host antes de la siguiente tarea.

```bash
# Solo en el Mac; no son comandos del examen
bash scripts/vm-lab.sh start
bash scripts/vm-lab.sh shell
# Para Linux: desde otra terminal del Mac
bash scripts/vm-lab.sh node cp
# Al acabar, en el Mac:
bash scripts/vm-lab.sh stop
```

No memorices YAML largo: practica localizar NetworkPolicy, Gateway/HTTPRoute, PV/PVC, probes y affinity. Kubernetes, Helm y Gateway API tienen documentación distinta; **no toda está en kubernetes.io**. etcd.io es fuente de estudio, no asumas que es un recurso permitido en CKA salvo que la tarea lo facilite.

### Correcciones principales respecto al adjunto

| Antes | Ahora |
| --- | --- |
| Completion sin cargar su función | `source <(kubectl completion bash)` antes de `complete` |
| `.status.containerRestartCount` | Campo real `containerStatuses[0].restartCount`, con su alcance |
| `set image --record` | Sin flag retirado; verificar rollout/historial |
| Borrado forzado y drain agresivo por rutina | Operación normal; excepciones solo con causa y consecuencias |
| Worker «idéntico al control plane» | Secuencia explícita y separación entre host kubectl/nodo Linux |
| `etcdctl snapshot status/restore` | `etcdutl`, membresía, revisión/compaction y verificación |
| `debug node` descrito como shell directo | Pod con `/host`, permisos y limitaciones |
| DNS de Pod asumido universal | DNS estable de Services; advertencia de implementación |
| Red/storage demasiado resumidos; sin Helm | EndpointSlices, políticas, HPA, routing, almacenamiento, Helm/Kustomize y CRDs |
