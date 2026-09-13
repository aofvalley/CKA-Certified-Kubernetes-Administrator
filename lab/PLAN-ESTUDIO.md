# Plan de estudio CKA: 13 → 22 de septiembre (examen: miércoles 23)

Plan operativo sobre **el lab de VMs ya instalado** (controlplane, node01 y node02 en Kubernetes 1.34.11, con Calico, Traefik, Gateway API, metrics-server y `standard` como StorageClass). Complementa la [ruta de diez días](README.md): aquí tienes qué hacer cada día, en qué orden y cuándo lo das por hecho.

- **Entre semana:** unas 3,5 h. **Fin de semana (19 y 20):** unas 6 h, porque ahí van los simulacros largos.
- **Pesos del examen:** troubleshooting 30 %, arquitectura/kubeadm 25 %, redes 20 %, workloads 15 %, storage 10 %.
- **Regla de oro:** leer el enunciado → resolver sin solución → verificar → solo entonces comparar con la solución. Si llevas más de 8 min atascado, lo apuntas y pasas al siguiente.

## Ritual diario (siempre igual)

```bash
cd "$HOME/Desarrollo/CKA-Certified-Kubernetes-Administrator"
bash scripts/vm-lab.sh start && bash scripts/vm-lab.sh status
bash scripts/vm-lab.sh shell          # kubectl/helm desde el Mac
bash scripts/vm-lab.sh node cp        # SSH a Ubuntu (otra pestaña)
```

| Bloque | Min | Qué |
| --- | --- | --- |
| Calentamiento | 15 | Sin apuntes: escribir de memoria 3 YAML (Pod, Deployment+Service, NetworkPolicy/RBAC) con `$do` y `k explain` |
| Ejercicios del día | 120 | Los de la tabla, cronometrados |
| Avería | 45 | Romper algo del día y arreglarlo (ver cada día) |
| Cierre | 20 | Apuntar fallos en `.lab/answers/errores.md` y repetir el peor ejercicio desde cero |

Al terminar: `bash scripts/vm-lab.sh stop`.

Formato de `.lab/answers/errores.md`: `fecha | ejercicio | tiempo | qué falló | causa raíz | comando que lo demuestra`.

---

## D1 · Domingo 13 (hoy) · Base + diagnóstico

| ✔ | Tarea | Tiempo objetivo |
| --- | --- | --- |
| [ ] | Diagnóstico sin ayuda: [01](../exercises/01-pod-basics/), [03](../exercises/03-configmap-secret/), [06](../exercises/06-deployment-rollout/), [04](../exercises/04-rbac/) | 45 min en total |
| [ ] | [02 multi-container / sidecar](../exercises/02-multi-container-pod/) | 15 |
| [ ] | [21 Jobs y CronJobs](../exercises/21-jobs-cronjobs/) | 15 |
| [ ] | Leer [chuleta de memoria](../cheatsheet/cka-cheatsheet-memoria.md) secciones 1–4 y [EXAM_STRATEGY.md](../EXAM_STRATEGY.md) | 30 |
| [ ] | Hacer ya la [comprobación PSI](https://syscheck.bridge.psiexams.com/) y confirmar la hora del examen en el portal | 10 |

**Avería:** Deployment con imagen inexistente → diagnosticar `ImagePullBackOff` con `describe`/eventos → `rollout undo`.
**Hecho si:** resuelves 01/03/06 sin mirar soluciones. Si hoy necesitas la solución en 2 o más de los 4, recorta D7 (Helm/Kustomize) y dale ese tiempo a los básicos.

## D2 · Lunes 14 · Redes (20 %)

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | Services (ClusterIP/NodePort), EndpointSlices, DNS: `nslookup svc.ns.svc.cluster.local` desde un Pod busybox | 30 |
| [ ] | [05 NetworkPolicy](../exercises/05-networkpolicy/) | 20 |
| [ ] | [28 NetworkPolicy compleja](../exercises/28-network-policy-complex/): default-deny + egress DNS 53 UDP/TCP | 25 |
| [ ] | [19 Ingress clásico](../exercises/19-ingress-classic/) con clase `traefik` y `curl -H Host` vía port-forward | 15 |

**Avería:** Service con selector o `targetPort` mal → `k get endpointslices` vacío → arreglar. Escalar CoreDNS a 0 y observar el síntoma.
**Hecho si:** demuestras con `wget`/`nc` una conexión permitida **y** una denegada.

## D3 · Martes 15 · Seguridad y scheduling

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | Repetir [04 RBAC](../exercises/04-rbac/) desde cero + `k auth can-i --as=system:serviceaccount:ns:sa` | 15 |
| [ ] | [08 drain/cordon](../exercises/08-node-drain-cordon/) sobre `node01` | 10 |
| [ ] | Taints/tolerations, nodeSelector y nodeAffinity (sin ejercicio: hazlo con `node02`) | 20 |
| [ ] | [22](../exercises/22-priorityclass/) + [24 PriorityClass](../exercises/24-priorityclass-patch/) | 25 |
| [ ] | [23 requests/limits](../exercises/23-resource-requests-tuning/), ResourceQuota y LimitRange | 20 |
| [ ] | [20 Pod Security Standards](../exercises/20-pod-security-standards/) (labels de namespace) | 15 |

**Avería:** Pod `Pending` por request mayor que el nodo, o por taint sin toleration → leer eventos → arreglar.
**Hecho si:** recuperas un Pod Pending explicando la causa exacta del evento.

## D4 · Miércoles 16 · Storage (10 %) + workloads

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | [12 PV/PVC](../exercises/12-storage-pv-pvc/): hostPath, accessModes, reclaimPolicy | 15 |
| [ ] | [25 WaitForFirstConsumer](../exercises/25-storage-waitforfirstconsumer/) (la clase `standard` del lab ya lo usa) | 20 |
| [ ] | [07 StatefulSet](../exercises/07-statefulset/) con volumeClaimTemplates | 15 |
| [ ] | [16 HPA](../exercises/16-hpa/) (`k top`, `autoscale --cpu=50%`) | 15 |
| [ ] | DaemonSet desde un Deployment editado, y `k rollout history/undo --to-revision` | 15 |
| [ ] | Chuleta de memoria secciones 5, 11 y 12 de memoria | 20 |

**Avería:** PVC `Pending` por clase inexistente o accessMode incompatible con el PV.
**Hecho si:** borras el Pod, lo recreas y los datos del PVC siguen ahí.

## D5 · Jueves 17 · Troubleshooting I (30 %, el más importante)

Todo por SSH: `bash scripts/vm-lab.sh node cp` (o `w1`) y `sudo -i`. **Antes de romper nada:** `cp -a /etc/kubernetes /root/bk-d5`. Nunca dejes copias dentro de `/etc/kubernetes/manifests`.

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | [10 static Pod](../exercises/10-static-pod/) en `node01` (localiza `staticPodPath` en `/var/lib/kubelet/config.yaml`) | 10 |
| [ ] | [17 kubectl debug](../exercises/17-kubectl-debug/) (contenedor efímero y `debug node/`) | 15 |
| [ ] | [11 troubleshoot cluster](../exercises/11-troubleshoot-cluster/) | 25 |
| [ ] | [29 endpoint de etcd roto](../exercises/29-troubleshoot-etcd-endpoint/) | 20 |

**Averías cronometradas (máx. 15 min cada una):**
1. En `node01`: `systemctl stop kubelet` → nodo NotReady → `journalctl -u kubelet` → arreglar.
2. En `node01`: ruta del CA errónea en `/var/lib/kubelet/config.yaml` → reiniciar kubelet → diagnosticar.
3. En `controlplane`: error tipográfico en un flag de `kube-apiserver.yaml` → la API no responde → `crictl ps -a` + `crictl logs` → arreglar.
4. En `controlplane`: `kube-scheduler.yaml` roto → Pods nuevos en Pending sin eventos de scheduling.

**Hecho si:** 3 de 4 resueltas en menos de 15 min cada una. Si no, repite las fallidas el D10 por la mañana.

## D6 · Viernes 18 · etcd + upgrade kubeadm (25 %)

**Hoy el cluster pasa a 1.35, la versión del examen.** No hay vuelta atrás sin `reset`.

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | etcd **backup** con `etcdctl snapshot save` (certificados sacados de `etcd.yaml`, no memorizados) | 15 |
| [ ] | etcd **restore**: crear un namespace `borrame`, `etcdutl snapshot restore --data-dir /var/lib/etcd-restore`, cambiar el `hostPath` en `etcd.yaml` y comprobar que `borrame` ya no existe | 35 |
| [ ] | [Upgrade 1.34 → 1.35](vms/upgrade.md) ([ejercicio 09](../exercises/09-kubeadm-upgrade/)): controlplane → drain `node01` → upgrade → uncordon → `node02` | 75 |
| [ ] | [30 TLS](../exercises/30-tls-configuration-update/) + `kubeadm certs check-expiration` | 20 |
| [ ] | Chuleta de memoria secciones 6, 7 y 9 | 15 |

**Hecho si:** `k get nodes` muestra los tres nodos en `v1.35.8` y Ready, y la restauración de etcd demostró que funcionaba.

## D7 · Sábado 19 · Herramientas + simulador killer.sh 1

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | [13 Helm](../exercises/13-helm-install-upgrade/): `repo add`, `install`, `upgrade --set`, `rollback`, `template` | 25 |
| [ ] | [14 Kustomize](../exercises/14-kustomize-overlays/) (`k apply -k`, `k kustomize`) | 20 |
| [ ] | [15 Gateway API](../exercises/15-gateway-api/): Gateway + HTTPRoute con clase `traefik` | 25 |
| [ ] | CRDs y operadores: `k get crd`, `k explain installation.spec` (Tigera), `k api-resources` | 15 |
| [ ] | **Tarde: killer.sh sesión 1, 120 min sin ayuda.** La sesión dura 36 h desde que la activas | 120 |
| [ ] | Corregir: clasificar cada fallo por dominio y apuntarlo en `errores.md` | 60 |

## D8 · Domingo 20 · Instalación desde cero + Mock 01

Guarda antes lo que quieras conservar: `reset` borra las tres VMs.

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | `bash scripts/vm-lab.sh reset bare --yes` y después `kubeadm init` + `join` a mano ([guía](vms/README.md#todos-los-ejercicios-con-sus-prerrequisitos)) | 45 |
| [ ] | [27 instalar Calico/Tigera](../exercises/27-cni-tigera-install/) con `vms/calico-values.yaml` → nodos Ready | 30 |
| [ ] | Leer [18](../exercises/18-cri-dockerd-setup/)/[26 cri-dockerd](../exercises/26-cri-dockerd-setup/): `dpkg -i`, `systemctl enable --now`, sysctl `net.ipv4.ip_forward`, `bridge-nf-call-iptables` | 20 |
| [ ] | `bash scripts/vm-lab.sh reset full --yes` (tarda: déjalo trabajando mientras repites fallos de killer.sh 1, que sigue activa) | 60 |
| [ ] | **[Mock 01](../mock-exams/MOCK-EXAM-01.md): `bash scripts/run-mock-exam.sh 1`**, 120 min | 120 |
| [ ] | Corregir con las soluciones | 45 |

## D9 · Lunes 21 · Simulador killer.sh 2

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | **killer.sh sesión 2**, 120 min, en condiciones de examen: una pantalla, sin chuleta, solo kubernetes.io/docs | 120 |
| [ ] | Corregir y repetir las 3 preguntas peores desde cero (la sesión sigue activa mañana) | 60 |

**Estrategia a ensayar:** primera pasada con lo rápido; lo que pase de ~8 min se marca y se deja. Segunda pasada con lo marcado. Últimos 15 min para verificar. En cada pregunta, lo primero es el contexto o SSH que pide el enunciado.

## D10 · Martes 22 · Repaso ligero, sin temas nuevos

| ✔ | Tarea | Tiempo |
| --- | --- | --- |
| [ ] | Repasar `errores.md` y repetir **solo** lo que falló dos veces | 60 |
| [ ] | [Mock 02](../mock-exams/MOCK-EXAM-02.md) a 60 min: solo las preguntas de tus dominios débiles | 60 |
| [ ] | Chuleta de memoria completa, una lectura | 20 |
| [ ] | Logística: DNI o pasaporte, mesa despejada, webcam, cerrar apps, repetir la comprobación PSI, hora del examen | 15 |
| [ ] | `bash scripts/vm-lab.sh stop` y **descansar** | — |

## D11 · Miércoles 23 · Examen

Al empezar, 1 min de configuración si hace falta: `alias k=kubectl`, `export do="--dry-run=client -o yaml"` y en `~/.vimrc` `set et sw=2 ts=2`. Después de cada tarea, verifica su resultado y sal del SSH antes de pasar a la siguiente. El aprobado está en el **66 %**.

---

### Indicadores de riesgo

- **Fin del D3:** si aún necesitas soluciones para Pod/Deployment/Service/RBAC, deja fuera 31 (Argo CD), 18/26 en profundidad y el Mock 02, y usa ese tiempo para repetir lo básico.
- **killer.sh 1 por debajo del 50 %:** es normal (es más difícil que el examen). Lo preocupante sería no mejorar en la sesión 2.
- **No tocar:** [31 Argo CD](../exercises/31-argocd-gitops-setup/) no está en el temario oficial; solo si sobra tiempo.
