# CKA — una chuleta para practicar y ganar tiempo

**Basada en tu chuleta adjunta:** conserva la creación imperativa, `$do`, `expose`, RBAC, rollouts, diagnóstico y las secuencias de kubeadm/etcd. Las versiones anteriores se unifican aquí.

**No ejecutes esta página de arriba abajo.** Prepara la terminal una vez; después consulta solo la operación que pide el ejercicio. Para aprender: tapa el comando, intenta escribirlo, consulta lo que falta y repítelo con otros valores. Memorizar YAML largo no es el objetivo.

[Volver a la rutina diaria](../README.md#rutina-diaria) · [Generadores](#4-creación-imperativa) · [Cambios rápidos](#5-modificar-sin-rehacer-el-manifiesto) · [Diagnóstico](#6-troubleshooting-según-el-síntoma) · [kubeadm](#11-upgrade-con-kubeadm) · [etcd](#12-etcd-backup-y-restore).

## 1. SIEMPRE: preparar Bash

**Una vez por terminal de trabajo.** En el lab, dentro de Ubuntu; en el examen, en el host asignado. Repetir estas líneas no borra ni despliega nada:

```bash
alias k=kubectl
alias kn='kubectl config set-context --current --namespace'
export do='--dry-run=client -o yaml'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

`k` ahorra escribir kubectl; `kn` selecciona namespace; `$do` **genera YAML sin crear el objeto**; las dos últimas líneas activan Tab también para `k`. En Bash, usa `$do` sin comillas para que se expanda en varios argumentos. No pegues este bloque en zsh.

**Vim, al abrir un YAML:** `:set et ts=2 sw=2 ai number`. `i` insertar · `Esc` volver a modo normal · `:wq` guardar/salir · `u` deshacer · `/texto` buscar. En la VM ya hay configuración de Vim; practica establecerla sin depender del lab.

No necesitas cargar diez aliases ni ejecutar `exam-setup.sh` para seguir esta ruta. **No prepares `$now` como borrado habitual**: `--force --grace-period=0` puede dejar procesos activos. Rapidez no significa saltarse una terminación segura.

## 2. CADA TAREA: host, contexto y namespace

Lee el host/SSH del enunciado **antes** de tocar el cluster:

```bash
hostname
k config get-contexts
```

Si la tarea exige otro contexto, `k config use-context CONTEXTO_DEL_ENUNCIADO`. Después selecciona el namespace con `kn "$NS"` y comprueba el `*` y la columna `NAMESPACE` de `k config get-contexts`. `$NS` debe contener el namespace real; en el lab lo defines al [preparar el día](../README.md#3-preparar-o-retomar-el-namespace-del-día).

**Seleccionar no crea el namespace.** En el examen no inventes nombres ni crees recursos no solicitados. SSH nuevo, otro usuario y Mac/VM pueden tener kubeconfigs diferentes. `-n otro` y `metadata.namespace` no se sustituyen por el namespace que seleccionaste.

## 3. Elegir el camino corto

| Qué pide la tarea | Qué haces |
| --- | --- |
| Crear algo que se expresa con flags | **Imperativo directo.** No generes/edites/apliques un YAML por obligación. |
| Crear con campos sin flags, o entregar un archivo | **Generar → editar solo lo necesario → aplicar.** Usa `$do > archivo.yaml`; para campos desconocidos, `k explain`. |
| Cambiar un recurso existente | **`set`, `scale`, `label`, `annotate` o un `patch` pequeño.** No lo recrees por comodidad. |
| Recurso sin generador, como NetworkPolicy/PVC/Gateway | Busca una plantilla en la documentación permitida y adapta los campos. No hace falta recordar todo el YAML. |

**La verificación no es opcional; la ceremonia extra sí.** `apply --dry-run=server` es útil para YAML complejo, no un paso obligatorio antes de cada creación sencilla. Solo valida admisión/esquema: no prueba imagen, scheduling, permisos de aplicación ni tráfico.

## 4. Creación imperativa

**Tapa la columna derecha y practica elegir el generador.** Son alternativas, no un script. Todos los recursos namespaced usan el namespace actual; añade `-n` si necesitas otro. `web`, imágenes y puertos son ejemplos: manda el enunciado.

| Quiero… | Comando que conviene tener en los dedos |
| --- | --- |
| Generar un Pod | `k run web --image=nginx:1.28 $do > pod.yaml` |
| Generar un Deployment de 3 réplicas | `k create deploy web --image=nginx:1.28 --replicas=3 $do > deploy.yaml` |
| Exponer un Deployment que **ya existe** | `k expose deploy web --name=web-svc --port=80 --target-port=80` |
| Guardar ese Service como YAML | `k expose deploy web --name=web-svc --port=80 --target-port=80 $do > svc.yaml` |
| Service NodePort | `k expose deploy web --name=web-nodeport --port=80 --target-port=80 --type=NodePort` |
| Service headless | `k create svc clusterip web-headless --clusterip=None --tcp=80:80 $do > headless.yaml` |
| ConfigMap desde un valor | `k create cm app --from-literal=MODE=practice` |
| ConfigMap desde un archivo existente | `k create cm app-file --from-file=./app.conf` |
| Secret con datos **ficticios de práctica** | `k create secret generic db --from-literal=pass=solo-practica` |
| Secret desde un archivo existente | `k create secret generic db-file --from-file=password=password.txt` |
| ServiceAccount | `k create sa deployer` |
| Job | `k create job once --image=busybox:1.37.0 -- sleep 30` |
| CronJob | `k create cronjob tick --image=busybox:1.37.0 --schedule='*/5 * * * *' -- date` |
| HPA, con Deployment existente | `k autoscale deploy web --min=2 --max=10 --cpu=70%` |
| Ingress, con Service existente | `k create ingress web --class=traefik --rule='app.cka.test/*=web-svc:80' $do > ingress.yaml` |

**El truco importante:** quitar `$do > archivo.yaml` crea directamente. Añadir `$do > archivo.yaml` a los generadores compatibles guarda el manifiesto en vez de crear el objeto; en Job/CronJob ponlo **antes de `--`**, que separa el comando del contenedor. `>` sobrescribe el archivo: trabaja en la carpeta del ejercicio.

Cuando has generado un archivo: `vim pod.yaml` → `k apply -f pod.yaml` → comprobar el requisito. No uses `apply -f .` por rutina si esa carpeta contiene manifiestos de otros ejercicios.

`run` no genera Deployments. `expose` consulta el recurso existente para deducir su selector, incluso con `$do`. Un `containerPort` no abre un puerto. No pegues credenciales reales en el historial; el ejemplo de Secret solo contiene datos ficticios.

**HPA:** `70%` es sobre requests, no limits, y requiere métricas. `--cpu=500m` sería un objetivo absoluto. El `--cpu-percent=70` del adjunto sigue aceptado por el cliente 1.35, pero está deprecado; practica `--cpu=70%`.

## 5. Modificar sin rehacer el manifiesto

```bash
k set image deploy/web nginx=nginx:1.28
k rollout status deploy/web --timeout=120s
k rollout history deploy/web
k rollout undo deploy/web
k scale deploy/web --replicas=3
k set env deploy/web --from=configmap/app
k set resources deploy/web -c nginx \
  --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=128Mi
k label pod web version=v1
k label pod web tier-
k annotate deploy/web motivo=practica --overwrite
```

Elige **solo el cambio solicitado**. `nginx` en `set image`/`set resources` es el **nombre del contenedor**: compruébalo. No uses `--record`, ya retirado. Para una revisión concreta: `k rollout undo deploy/web --to-revision=2`, solo si existe. No mantengas `scale` manual compitiendo con HPA.

Si no existe un comando específico, parchea el campo. Ejemplo **si la PriorityClass `high-priority` ya existe**:

```bash
k patch deploy web --type=merge \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
k get deploy web -o jsonpath='{.spec.template.spec.priorityClassName}{"\n"}'
k rollout status deploy/web --timeout=120s
```

JSON Merge Patch reemplaza listas enteras: no lo uses a ciegas sobre `containers`. Cambiar la plantilla de un Deployment crea Pods nuevos; muchos campos de un Pod suelto son inmutables. Verifica también el estado final, no solo el valor del campo.

## 6. Troubleshooting según el síntoma

**No ejecutes todos los diagnósticos por costumbre.** Un Pod roto no exige empezar reiniciando kubelet.

| Síntoma | Primera consulta | Qué buscas |
| --- | --- | --- |
| Pending | `k describe pod NOMBRE` | Eventos: requests, taints, affinity, PVC, cuotas |
| ImagePullBackOff | `k describe pod NOMBRE` | Imagen/tag, credenciales y acceso al registro |
| CrashLoopBackOff | `k logs NOMBRE -c CONTENEDOR --previous` | Error anterior; después Last State, comando, configuración/probes |
| CreateContainerConfigError | `k describe pod NOMBRE` | ConfigMap/Secret o clave que falta |
| Service sin tráfico | `k get endpointslices -l kubernetes.io/service-name=SERVICIO` | Selector y Pods Ready; después puerto real y NetworkPolicy |
| Forbidden | `k auth can-i VERBO RECURSO -n NAMESPACE` | Identidad, recurso/subrecurso, ámbito |
| Nodo NotReady | `k describe node NODO` | Conditions; después kubelet/runtime por SSH |
| API caída | `sudo crictl ps -a` en el control plane | Primero confirmar host/endpoint/red; luego etcd/static Pods/certificados |

Herramientas para la duda concreta; sustituye los nombres en mayúsculas:

```bash
k get pods -o wide
k get events --sort-by=.metadata.creationTimestamp
k describe pod POD
k logs POD -c CONTENEDOR --tail=50
k logs POD -c CONTENEDOR --previous
k exec POD -c CONTENEDOR -- COMANDO
k explain pod.spec.containers.resources
k explain deployment.spec.template --recursive
k get pods --sort-by='.status.containerStatuses[0].restartCount'
k get --raw='/readyz?verbose'
```

El orden por reinicios mira solo el **primer contenedor**, no la suma. `describe` completo antes de recortarlo con `tail`: también necesitas Conditions/Last State. `Running` no equivale a Ready; código 137 no demuestra OOM sin el motivo correspondiente.

Sin herramientas en la imagen: `k debug -it POD --image=busybox:1.37.0 --target=CONTENEDOR`. El contenedor efímero queda registrado en el Pod. `kubectl debug node/node01 -it --image=ubuntu:24.04` crea un **Pod** con el nodo montado en `/host`, no un SSH; depende de la API y no es privilegiado por defecto. En el lab, para administrar el nodo entra por SSH.

## 7. RBAC

<details>
<summary>Generar permisos y probar lo permitido y lo denegado</summary>

`$NS` es el namespace real elegido. Estos nombres son ejemplos:

```bash
k -n "$NS" create sa deployer
k -n "$NS" create role pod-reader --verb=get,list,watch --resource=pods
k -n "$NS" create rolebinding pod-reader \
  --role=pod-reader --serviceaccount="$NS:deployer"
k auth can-i get pods -n "$NS" --as="system:serviceaccount:$NS:deployer"
k auth can-i delete pods -n "$NS" --as="system:serviceaccount:$NS:deployer"
k auth can-i get pods --subresource=log -n "$NS" --as="system:serviceaccount:$NS:deployer"
```

Esperado: **yes / no / no**, si no hay otros permisos. `pods`, `pods/log` y `pods/exec` son recursos distintos.

Si la tarea pide permisos globales, también hay generadores:

```bash
k create clusterrole node-reader --verb=get,list --resource=nodes
k create clusterrolebinding node-reader --clusterrole=node-reader \
  --serviceaccount="$NS:deployer"
k auth can-i get nodes --as="system:serviceaccount:$NS:deployer"
```

Role/RoleBinding son namespaced. ClusterRole define permisos; por sí solo **no los concede**. Un RoleBinding puede usar un ClusterRole y limitar sus permisos namespaced a ese namespace. Un ClusterRoleBinding concede a nivel cluster. No des `cluster-admin` para arreglar un Forbidden; `roleRef` es inmutable.

</details>

## 8. Nodos y scheduling

<details>
<summary>Cordon, drain, taints, recursos y selección</summary>

Desde el control plane o el host con kubeconfig administrativo:

```bash
k cordon node01
k get pdb -A
k drain node01 --ignore-daemonsets --timeout=120s
# Solo tras terminar el mantenimiento:
k uncordon node01
k taint node node01 dedicated=lab:NoSchedule
k taint node node01 dedicated=lab:NoSchedule-
k label node node01 disk=ssd
k top nodes
k top pods --sort-by=cpu
k create priorityclass high-priority --value=1000 --description='Practice priority'
```

`cordon` impide nuevas asignaciones, no expulsa Pods. `drain` respeta PDB; `--force` permite Pods sin controlador, **no salta PDB**. No añadas `--force`, `--disable-eviction` o `--delete-emptydir-data` sin entender el bloqueo y sus consecuencias.

`nodeSelector`/affinity eligen; tolerations **permiten**, no fuerzan ir a un nodo. `NoSchedule` no expulsa existentes; `NoExecute` sí puede hacerlo. Con `WaitForFirstConsumer`, evita `nodeName`, que omite el scheduler.

Scheduler usa **requests**; `100m` = 0,1 CPU. Readiness retira tráfico, liveness reinicia y startup protege el arranque. Los cambios en ConfigMap/Secret usados por variable de entorno requieren nuevos Pods; `subPath` no se actualiza automáticamente.

</details>

## 9. Red, DNS y NetworkPolicy

<details>
<summary>Comprobar tráfico sin adivinar; selectores AND/OR y DNS</summary>

```bash
k get svc web-svc -o yaml
k get pods --show-labels
k get endpointslices -l kubernetes.io/service-name=web-svc -o yaml
k run dns-check --image=busybox:1.37.0 --restart=Never --rm -i \
  -- nslookup "web-svc.$NS.svc.cluster.local"
k run http-check --image=busybox:1.37.0 --restart=Never --rm -i \
  -- wget -T 3 -qO- http://web-svc:80
k -n kube-system get pods -l k8s-app=kube-dns
k -n kube-system logs deploy/coredns --tail=50
k get netpol
k describe netpol
```

DNS estable: `servicio.namespace.svc.cluster.local`; el dominio puede variar. No des por garantizado el DNS basado en la IP del Pod. `--rm` limpia solo ese Pod cliente al salir; no es una instrucción para borrar el namespace del día.

**Diagnóstico:** selector → Ready → EndpointSlices → puerto real → DNS → políticas/CNI. EndpointSlices vacíos no prueban que el puerto esté mal: empieza por selector y readiness. `port` es del Service; `targetPort`, donde escucha el proceso. Un LoadBalancer requiere implementación; NodePort usa normalmente 30000–32767.

**NetworkPolicy:** el CNI debe aplicarla. Se aíslan ingress/egress por separado; reglas se suman. Si ambos extremos están aislados, deben permitir la conexión el egress del origen y el ingress del destino.

Fragmento de `spec.ingress`: permitir TCP/80 desde Pods `role: frontend` **del namespace `clients`**:

```yaml
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

Mismo elemento de `from` = **AND**; elementos distintos = **OR**. El fragmento necesita un NetworkPolicy completo: `apiVersion`, `kind`, metadata, `spec.podSelector` y `policyTypes`. Un `podSelector` sin `namespaceSelector` selecciona Pods del namespace de la política.

Si necesitas egress DNS, contempla **UDP y TCP 53** hacia el DNS real, no una salida general a cualquier IP por costumbre. Ejemplo de fragmento `spec` para CoreDNS:

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

Comprueba labels y si existe NodeLocal DNS antes de reutilizarlo. Añade las demás salidas exigidas. Demuestra conexión permitida **y** denegada; un timeout por DNS roto no demuestra la política.

</details>

## 10. Storage, Ingress y Gateway API

<details>
<summary>Campos que deben encajar y prueba del resultado</summary>

```bash
k get pv,storageclass
k get pvc
k describe pvc DATOS
k get ingressclass,gatewayclass
k get ingress,gateway,httproute
k describe gateway WEB
k get httproute WEB -o yaml
```

**Storage:** PV global, PVC del namespace del Pod. Binding: clase, capacidad, accessModes, volumeMode y topología. `storageClassName: ""` solicita sin clase; omitirlo puede usar la predeterminada. `WaitForFirstConsumer`: un PVC Pending puede estar esperando al scheduler, no roto.

RWO = escritura desde un nodo, no necesariamente un Pod. RWOP = un Pod, con CSI compatible. `Retain` conserva almacenamiento para recuperación manual; `Delete` puede borrar **los datos**. En el Pod: `volumes[].persistentVolumeClaim.claimName` y `containers[].volumeMounts`.

Para demostrar persistencia, escribe un marcador y recrea **solo el Pod consumidor**, no el PVC. El lab usa StorageClass `standard`, con volúmenes locales: no son almacenamiento compartido.

**Routing:** en el lab las clases son `traefik`; en examen usa las pedidas. Ingress/Gateway no instalan el controlador. GatewayClass `Accepted`; Gateway `Programmed`; HTTPRoute, condiciones del parent `Accepted/ResolvedRefs`; después **HTTP con el Host correcto**.

`backendRefs.port` es el puerto del Service. Backend entre namespaces: revisar `ReferenceGrant`; rutas en otro namespace que su Gateway: `allowedRoutes`. [Plantilla de práctica](../skeletons/gateway-api.yaml); en el examen, documentación permitida.

Para probar sin una IP externa:

```bash
k port-forward svc/web-svc 8080:80 --address 127.0.0.1
```

Déjalo abierto; consulta `http://127.0.0.1:8080/` desde **otra terminal en el mismo host**. Para Ingress/Gateway del lab, el túnel se hace a `svc/traefik` en el namespace `traefik` y el cliente envía el Host configurado. `Ctrl+C` cierra el túnel, no borra la aplicación.

</details>

## 11. Upgrade con kubeadm

<details>
<summary>Secuencia del primer control plane y diferencia de los workers</summary>

**Solo Ubuntu, no macOS/kind.** Respaldo y salud antes de empezar. Primer control plane → otros control planes → workers, uno a uno; no saltes minor.

Ejemplo **del lab 1.34.11 → 1.35.8**. En el examen sustituye las versiones por las pedidas. Primero cambia el repositorio a la minor destino:

```bash
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
k get nodes -o wide
```

El cambio del repositorio `pkgs.k8s.io` de **v1.34 a v1.35** es el paso que no debes olvidar. No continúes si falla drain o un paso anterior.

**Worker:** drenar desde el control plane → SSH al worker → cambiar repositorio y actualizar/retener kubeadm → `sudo kubeadm upgrade node` → actualizar/retener kubelet y kubectl → daemon-reload/restart → volver al control plane → uncordon → Ready y versión.

No es «idéntico al control plane»: en workers no se ejecuta `plan/apply` ni se actualiza kubelet antes de `upgrade node`. Control planes adicionales usan `upgrade node`. Los workers del lab no tienen kubeconfig administrativo.

[Procedimiento local completo](../lab/vms/upgrade.md). Instalación desde cero: runtime/cgroups/red/paquetes → init → kubeconfig → CNI → join → nodos y DNS. No instales un segundo CNI. HA requiere endpoint estable, control planes adicionales y quorum etcd; tres nodos con un solo control plane no son HA.

</details>

## 12. etcd: backup y restore

<details>
<summary>etcdctl guarda; etcdutl inspecciona y restaura en etcd 3.6</summary>

En el control plane, descubre endpoint, certificados, nombre del miembro y peer URL en el manifiesto. Ejemplo de rutas **del lab kubeadm**:

```bash
sudo grep -E 'name=|initial-cluster=|advertise-peer-urls|listen-client-urls|cert|key|data-dir' \
  /etc/kubernetes/manifests/etcd.yaml
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /opt/snap.db
sudo etcdutl snapshot status /opt/snap.db -w table
```

**Restore revierte cambios posteriores al snapshot en todo el cluster.** Solo si se solicita, con copia previa del manifiesto fuera de `staticPodPath`. Para **un único miembro**: retirar el manifiesto etcd y confirmar su parada con `crictl` → restaurar a un directorio nuevo → ajustar montaje → reponer el manifiesto → verificar.

Este ejemplo utiliza nombre y peer **del lab**; vuelve a descubrirlos en otro entorno. `/var/lib/etcd-restore` debe ser un destino nuevo:

```bash
sudo etcdutl snapshot restore /opt/snap.db \
  --data-dir=/var/lib/etcd-restore \
  --name=controlplane \
  --initial-cluster=controlplane=https://192.168.57.10:2380 \
  --initial-advertise-peer-urls=https://192.168.57.10:2380 \
  --bump-revision=1000000000 --mark-compacted
```

En el manifiesto guardado, cambia **`volumes[].hostPath.path` de `etcd-data`** al destino restaurado. Si el montaje interno sigue siendo `/var/lib/etcd`, conserva `mountPath` y `--data-dir` internos. Reponlo en su ubicación original; no dejes archivos de respaldo dentro de `/etc/kubernetes/manifests/`.

El bump/compaction evita revisiones antiguas en clientes Kubernetes; confirma soporte con `etcdutl snapshot restore --help`. Conserva los datos originales. No extrapoles esta receta de un único miembro a HA.

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
k get --raw='/readyz'
k get nodes
```

Después comprueba los objetos esperados del snapshot. El estado de etcd **no respalda los contenidos de los PV ni tus archivos de Ubuntu**. Fuente de estudio: [recuperación de etcd 3.6](https://etcd.io/docs/v3.6/op-guide/recovery/).

</details>

## 13. Linux y rutas de kubeadm

<details>
<summary>Diagnóstico por SSH, incluso sin API</summary>

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet -n 60 --no-pager
sudo crictl ps -a
sudo crictl logs ID_DEL_CONTENEDOR
sudo grep staticPodPath /var/lib/kubelet/config.yaml
sudo kubeadm certs check-expiration
df -h
df -i
sudo ss -lntp
```

| Qué | Ruta habitual; confirmar en el nodo |
| --- | --- |
| Static Pods | `/etc/kubernetes/manifests/`; manda `staticPodPath` |
| Kubeconfigs | `/etc/kubernetes/*.conf` |
| Configuración kubelet | `/var/lib/kubelet/config.yaml` |
| Flags kubeadm / override Ubuntu | `/var/lib/kubelet/kubeadm-flags.env` / `/etc/default/kubelet` |
| Certificados / datos etcd | `/etc/kubernetes/pki/` / `/var/lib/etcd` |
| Configuración / binarios CNI | `/etc/cni/net.d/` / `/opt/cni/bin/` |
| Socket containerd / cliente CRI | `/run/containerd/containerd.sock` / `/etc/crictl.yaml` |
| Logs de contenedores | `/var/log/containers/`; también `crictl logs` |

Static Pod = archivo gestionado por kubelet. Borrar su mirror Pod con kubectl no elimina la carga. Guarda respaldos **fuera** de `staticPodPath`. Con la API caída no tienes kubectl para administrar, pero sí SSH, `journalctl`, `crictl` y archivos.

</details>

## 14. Helm, Kustomize y CRDs

<details>
<summary>Inspeccionar, renderizar, aplicar y verificar</summary>

`repo/chart`, `VERSION`, `release`, `REVISION` y rutas son marcadores. Configura el repositorio/OCI que pide la tarea:

```bash
helm list -A
helm show values repo/chart --version VERSION
helm template release repo/chart --version VERSION -n "$NS" -f values.yaml
helm upgrade --install release repo/chart --version VERSION -n "$NS" \
  --create-namespace -f values.yaml --wait --timeout 3m
helm status release -n "$NS"
helm history release -n "$NS"
helm rollback release REVISION -n "$NS" --wait
k kustomize overlays/prod
k apply -k overlays/prod
k get crd
k api-resources
```

Kustomize: cambia base/overlay, no solo una copia renderizada. CRD define el tipo, CR es instancia, operador reconcilia. No necesitas memorizar valores de charts ni CRDs completos.

Helm está instalado en **el Mac**, no en las VMs: para ese ejercicio usa `bash scripts/vm-lab.sh shell` desde el Mac y selecciona allí también el namespace. [Acceso y archivos por host](../lab/vms/README.md#entrar-linux-de-verdad).

</details>

## 15. Cerrar una tarea sin regalar puntos

Requisito demostrado, no solo «created»/«configured»: nombre/namespace/ruta correctos, configuración y Ready; tráfico para Services/rutas; permiso positivo y negativo para RBAC/políticas; datos para PVC; Ready y uncordon para mantenimiento. Guarda archivos donde se pidan y sal del host antes de otra tarea.

**Para estudiar:** intenta primero, consulta un campo/comando, vuelve a escribir sin mirar y repite otro día. Si necesitas ayuda, pide una pista del siguiente paso, no la solución completa. **En simulacros:** dos pasadas; si no avanzas en 6–8 minutos, marca y sigue; reserva 15–20 minutos finales para comprobar.

<details>
<summary>Qué se ha corregido del adjunto y qué consultar, no memorizar</summary>

Se conservan los aceleradores; no los errores que harían perder tiempo:

| En el adjunto | En esta chuleta |
| --- | --- |
| Completion sin cargar su función | `source` antes de `complete` |
| `.status.containerRestartCount` | `containerStatuses[0].restartCount`, con su alcance |
| `set image --record` | Sin flag retirado |
| `--force` y `$now` por rutina | Solo operaciones excepcionales justificadas, no calentamiento |
| Worker «idéntico al control plane» | Separar drain, SSH, `upgrade node` y actualización de kubelet |
| `etcdctl snapshot status/restore` | `etcdutl` para etcd 3.6, con membresía y revisión |
| `debug node` como SSH / endpoints vacíos = puerto incorrecto | Pod de depuración / comprobar selector y readiness primero |

No memorices manifiestos enteros de NetworkPolicy, Gateway/HTTPRoute, PV/PVC, probes, affinity o CRDs. Practica encontrarlos y modificarlos con rapidez. Kubernetes, Helm y Gateway API tienen documentación distinta; no todo está en kubernetes.io.

**Este archivo y Copilot son herramientas de preparación, no recursos permitidos durante el examen.** Comprueba las [reglas oficiales](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed); no asumas que puedes abrir un repo personal o etcd.io si la tarea no lo facilita.

Fuentes de contraste: [kubectl](https://kubernetes.io/docs/reference/kubectl/quick-reference/) · [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) · [HPA 1.35](https://v1-35.docs.kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/) · [upgrade kubeadm 1.35](https://v1-35.docs.kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) · [etcd 3.6](https://etcd.io/docs/v3.6/op-guide/recovery/).

</details>
