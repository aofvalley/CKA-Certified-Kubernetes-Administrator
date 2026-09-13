# Laboratorio principal CKA: Ubuntu, SSH y kubeadm

Este laboratorio sustituye a kind como entorno principal de práctica. Usa **tres VMs Ubuntu 24.04** con **Kubernetes 1.34.11**, instalado mediante paquetes `apt` y `kubeadm`. El objetivo es practicar tú la actualización a **1.35.8**, no ejecutarla automáticamente durante la instalación.

La topología toma como referencia `lab-setup/mac-silicon` de `techiescamp/cka-certification-guide`. A diferencia de esa base, incluye instalación de Kubernetes, unión de workers, runtime, CNI y complementos. El otro directorio no se modifica.

## Primera instalación

Requiere macOS, Vagrant 2.4.9 o compatible, VirtualBox 7.2 con soporte para tu arquitectura, Helm 3, curl y conexión a Internet. **No necesita Docker, Multipass ni VMware Fusion.** No ejecutes Vagrant con `sudo`: mezclar ejecuciones como root y como tu usuario crea estados distintos.

Usa siempre `scripts/vm-lab.sh`, no `vagrant` directamente: el wrapper selecciona el directorio privado de estado. El Vagrantfile rechaza una invocación que no seleccione ese estado para evitar crear otro juego de VMs accidentalmente.

```bash
# Desde la raíz de este repositorio
bash scripts/vm-lab.sh doctor
bash scripts/vm-lab.sh up
bash scripts/vm-lab.sh check
```

| VM / alias | IP privada | CPU | RAM |
| --- | --- | --- | --- |
| controlplane / cp | 192.168.57.10 | 2 | 3 GiB |
| node01 / w1 | 192.168.57.11 | 2 | 2,5 GiB |
| node02 / w2 | 192.168.57.12 | 2 | 2,5 GiB |

Son **8 GiB de RAM** en total; reserva al menos 30 GiB libres para imágenes, discos y ejercicios. La imagen base es `bento/ubuntu-24.04` versión `202510.26.0`, ARM64 en Apple Silicon y AMD64 en Mac Intel. Los discos virtuales crecen con el uso. Evita ejecutar a la vez el cluster kind u otras VMs pesadas.

La red de nodos es **host-only**, no un puente a tu Wi-Fi. Cada VM tiene además NAT para descargar paquetes; Vagrant administra SSH. Calico usa `172.20.0.0/16` y los Services `10.96.0.0/12`. Si tu VPN o tus redes usan estos rangos, resuelve el solapamiento **antes** de crear el cluster. No se modifica `/etc/hosts` ni la configuración de shell del Mac.

Los kubeconfigs, claves SSH, estado de Vagrant y herramientas locales están bajo `.lab/vms/`, excluido de Git. No publiques esa carpeta. Se descarga y verifica por SHA-256 un **kubectl 1.35.8 exclusivo del laboratorio**, compatible con los servidores 1.34 y 1.35; no se sustituye tu kubectl global.

## Entrar: Linux de verdad

```bash
bash scripts/vm-lab.sh node cp
sudo -i
kubectl get nodes -o wide
systemctl status kubelet
journalctl -u kubelet -n 30
crictl ps
ls /etc/kubernetes/manifests
```

`exit` sale del shell root; otro `exit` cierra SSH. Abre otra terminal para cada worker:

```bash
bash scripts/vm-lab.sh node w1
sudo -i
```

El control plane tiene kubeconfig administrativo para `vagrant` y `root`; los workers **no** reciben credenciales administrativas. Ejecuta `kubectl drain` y `uncordon` desde el control plane o desde el shell del Mac, no desde un worker sin kubeconfig.

También puedes administrar recursos desde macOS:

```bash
bash scripts/vm-lab.sh shell
k get nodes
mkdir -p .lab/answers/day-01
exit

bash scripts/vm-lab.sh kubectl get pods -A
bash scripts/vm-lab.sh helm list -A
```

**`shell` sigue siendo macOS**, con aliases, Vim y kubeconfig aislados. **`node` entra por SSH en Ubuntu**. `apt`, `systemctl`, `journalctl`, `kubeadm` y los cambios de `/etc/kubernetes` se ejecutan en Ubuntu. Dentro de SSH, guarda tus respuestas en la VM o transfiérelas al Mac antes de destruirla: no hay carpeta compartida automática.

## Complementos

| Componente | Versión / configuración |
| --- | --- |
| Kubernetes | 1.34.11; kubeadm, kubelet y kubectl fijados y retenidos con `apt-mark hold` |
| containerd | Paquete de Ubuntu 24.04; cgroups systemd, socket `/run/containerd/containerd.sock` |
| crictl | Paquete `cri-tools` del repositorio Kubernetes; endpoint configurado |
| etcdctl / etcdutl | 3.6.5, binarios verificados por SHA-256 |
| Calico / Tigera | 3.32.2, VXLAN sin BGP; selección explícita de la red privada |
| Metrics Server | 0.9.0 |
| Traefik | Chart 41.5.0; IngressClass y GatewayClass `traefik` |
| Gateway API | CRDs estándar 1.6.1 |
| local-path-provisioner | 0.0.32; StorageClass predeterminada `standard`, WaitForFirstConsumer |

Metrics Server utiliza `--kubelet-insecure-tls` **solo para este laboratorio**; no es una recomendación para producción. Los volúmenes son locales al nodo, no almacenamiento compartido ni CSI de producción. Un Service LoadBalancer no obtiene automáticamente una IP.

Para Ingress y Gateway API utiliza clase `traefik`. Desde macOS:

```bash
bash scripts/vm-lab.sh kubectl -n traefik port-forward service/traefik 8080:80 --address 127.0.0.1
# En otra terminal, después de crear tu ruta:
curl -H 'Host: app.cka.test' http://127.0.0.1:8080/
```

## Uso diario y recuperación

```bash
bash scripts/vm-lab.sh status
bash scripts/vm-lab.sh stop     # Apaga solo estas VMs; conserva sus discos
bash scripts/vm-lab.sh start    # Arranca sin reinstalar ni corregir ejercicios
```

`up` permite continuar una instalación interrumpida. No degrada paquetes de nodos ya provisionados, no vuelve a unir workers existentes y solo instala automáticamente los complementos si la instalación inicial no terminó. **No es un reparador de averías** ni una herramienta de uso diario.

`addons` reconcilia explícitamente los complementos con la configuración del repositorio: puede deshacer ejercicios sobre Calico, Metrics Server, almacenamiento y Traefik. No lo uses mientras estés diagnosticando una avería.

### Después de una práctica destructiva: reset reproducible

No depende de que Kubernetes responda, de sus certificados ni del runtime: Vagrant elimina las tres VMs del laboratorio y las reconstruye desde la imagen base. **Se pierden todos los datos de las tres VMs**, incluidos PVC y respuestas guardadas solo dentro de Ubuntu. Antes de hacerlo, guarda los manifiestos y notas que quieras conservar en `.lab/answers/` del **Mac**.

```bash
# Volver al cluster completo 1.34: VMs, init/join, complementos y check funcional
bash scripts/vm-lab.sh reset full --yes

# Volver a Ubuntu con paquetes, SIN cluster ni CNI: practicar instalación/CRI/CNI
bash scripts/vm-lab.sh reset bare --yes
```

El modo es obligatorio y ambos comandos exigen `--yes`; no borran nada si falta. `full` solo anuncia éxito después de la comprobación funcional. `bare` deja intencionadamente los nodos sin `init/join`: no estarán Ready ni habrá API todavía. La versión inicial siempre es **1.34.11**, aunque el cluster anterior estuviera actualizado a 1.35.8.

Si una descarga o instalación se interrumpe **después del borrado**, corrige la conexión y continúa con `up` para modo full o `machines` para modo bare; no repitas `reset`, porque volvería a destruir lo ya creado. Se reutiliza la imagen base descargada por Vagrant, pero siguen haciendo falta paquetes e imágenes de contenedores: no es una recuperación instantánea ni sin conexión.

Se conservan las respuestas del Mac en `.lab/answers/`, el cliente kubectl local y el laboratorio Docker. `down --yes` sigue disponible si solo quieres borrar las VMs sin recrearlas. No uses `VBoxManage unregistervm` indiscriminadamente, `vagrant global-status` para borrar otras VMs, ni limpieza global de Docker.

`check` verifica SSH, servicios, swap desactivado, paquetes y CRI; después prueba tres nodos Ready, DNS y HTTP entre workers, un PVC con datos, NetworkPolicy permitida/denegada, Ingress, Gateway/HTTPRoute y métricas/HPA. Crea y elimina únicamente un namespace temporal propio; necesita ambos workers sin cordon.

## Todos los ejercicios, con sus prerrequisitos

Ya no se separan ejercicios por Docker frente a VMs: usa este mismo entorno para los ejercicios del repositorio. Los enunciados siguen requiriendo preparar su estado inicial:

| Práctica | Cómo prepararla aquí |
| --- | --- |
| Recursos Kubernetes, redes, RBAC, Helm, almacenamiento | Cluster completo creado con `up`; adaptar nodos a `controlplane`, `node01`, `node02` y clases a `standard`/`traefik` |
| 09: upgrade kubeadm | Sigue [la práctica 1.34 → 1.35](upgrade.md); empieza antes de actualizar |
| 10, 11, 17, 29 y 30: sistema, etcd y TLS | SSH al nodo correcto; respaldos **fuera** de `/etc/kubernetes/manifests` |
| 18 y 26: CRI-dockerd | VM desechable de este mismo lab; no sustituir containerd en un nodo activo sin practicar primero drain, configuración de kubelet y recuperación |
| 27: instalar CNI desde cero | Recrear las VMs y usar `machines`; ejecutar `kubeadm init/join` manualmente y después instalar un único CNI |
| 31: Argo CD | Opcional tras dominar el núcleo del temario; requiere instalación adicional |

Para practicar instalación desde cero, `machines` prepara Ubuntu, containerd y los paquetes, pero **no ejecuta `kubeadm init/join` ni instala CNI**:

```bash
# Solo después de guardar tus respuestas y aceptar la pérdida de las VMs:
bash scripts/vm-lab.sh reset bare --yes
bash scripts/vm-lab.sh node cp
sudo -i
kubeadm init --kubernetes-version=v1.34.11 \
  --apiserver-advertise-address=192.168.57.10 \
  --control-plane-endpoint=192.168.57.10:6443 \
  --pod-network-cidr=172.20.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --cri-socket=unix:///run/containerd/containerd.sock
export KUBECONFIG=/etc/kubernetes/admin.conf
kubeadm token create --ttl 15m --print-join-command
```

Ejecuta el join resultante en cada worker como root. Los nodos quedarán NotReady hasta instalar CNI: es esperado. Al instalar Calico usa el CIDR `172.20.0.0/16` y la autodetección de IP privada de [calico-values.yaml](calico-values.yaml), no la interfaz NAT. No instales un segundo CNI sobre el primero. Para convertir tu instalación manual en el entorno completo del repositorio, `up` reutiliza el control plane y los workers, exporta el kubeconfig y añade los complementos pendientes; úsalo solo cuando no hayas instalado ya otro CNI.

Esto se aproxima mucho más a la **administración Linux del examen**, pero no reproduce el escritorio PSI, la arquitectura AMD64 en un Mac ARM64, varios clusters ni un control plane HA. Para practicar HA habría que añadir control planes y un endpoint balanceado; no se simula con tres nodos de los que solo uno es control plane. Mantén los simuladores como práctica cronometrada, no como sustituto obligatorio de los ejercicios Linux.
