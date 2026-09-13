# Guía del estudiante: entrar, practicar y recuperar el laboratorio CKA

**Empieza aquí.** Este documento explica el uso diario; la [guía técnica](vms/README.md) explica la instalación. Tu entorno principal son **tres VMs Ubuntu**, no Docker. Empieza en Kubernetes **1.34.11** y lo actualizarás tú a **1.35.8**.

**Material de estudio:** [chuleta de memoria](../cheatsheet/cka-cheatsheet-memoria.md) · [referencia extensa](../cheatsheet/cka-cheatsheet-es.md) · [ruta de diez días](README.md).

## 1. Activar el lab al empezar el día

Abre Terminal en tu **Mac** y entra en el repositorio:

```bash
cd "$HOME/Desarrollo/CKA-Certified-Kubernetes-Administrator"
bash scripts/vm-lab.sh start
bash scripts/vm-lab.sh status
```

`start` enciende las VMs sin reinstalar Kubernetes ni corregir tus ejercicios. No necesitas arrancar Docker ni abrir la ventana de VirtualBox.

Espera a que `controlplane`, `node01` y `node02` aparezcan **Ready**. Tras un arranque, los servicios y las métricas pueden tardar en estar disponibles; vuelve a consultar `status`. Si no se recuperan, ve a [diagnóstico](#9-si-algo-no-funciona).

**Solo para la primera instalación, o para continuar una instalación interrumpida:**

```bash
bash scripts/vm-lab.sh doctor
bash scripts/vm-lab.sh up
bash scripts/vm-lab.sh check
```

No ejecutes `reset` para encender un lab apagado. No uses `sudo vagrant up` ni otro `vagrant up` directamente: el script selecciona el estado privado correcto.

## 2. Dónde estás y qué comandos van en cada sitio

| Lugar | Cómo entrar desde el Mac | Qué haces aquí |
| --- | --- | --- |
| Terminal normal del Mac | Abrir Terminal y entrar en el repositorio | `start`, `stop`, `status`, `reset`; gestionar archivos locales |
| Shell de práctica del Mac | `bash scripts/vm-lab.sh shell` | `kubectl`, Helm, editar YAML y guardar respuestas en el repositorio |
| Ubuntu `controlplane` | `bash scripts/vm-lab.sh node cp` | `kubectl` y, con sudo, kubeadm, etcd, certificados y static Pods |
| Ubuntu `node01` | `bash scripts/vm-lab.sh node w1` | Administración Linux del primer worker |
| Ubuntu `node02` | `bash scripts/vm-lab.sh node w2` | Administración Linux del segundo worker |

**Regla fundamental: `shell` NO entra en Linux; `node` SÍ entra por SSH.** `apt`, `systemctl`, `journalctl` y `kubeadm` van dentro de Ubuntu.

Si dudas, ejecuta:

```bash
hostname
whoami
pwd
```

En el shell del Mac verás un prompt que empieza por `[CKA VMs | macOS]`. Dentro de Ubuntu, `hostname` será `controlplane`, `node01` o `node02`; el usuario inicial es `vagrant`.

Las IP privadas son `192.168.57.10`, `.11` y `.12`, respectivamente. Para entrar, usa los alias `cp`, `w1`, `w2`: no necesitas memorizar puertos ni claves SSH.

## 3. Trabajar desde el Mac o desde Ubuntu

### Recursos Kubernetes: empezar desde el Mac

```bash
# Mac, desde la raíz del repositorio
bash scripts/vm-lab.sh shell
k config current-context
k get nodes -o wide
helm list -A
```

`k` es un alias de `kubectl`; `$do` equivale a `--dry-run=client -o yaml`. El cliente y kubeconfig quedan aislados para este lab. `exit` te devuelve a la terminal normal; **no apaga las VMs**.

También puedes ejecutar un comando suelto, sin abrir el shell:

```bash
bash scripts/vm-lab.sh kubectl get pods -A
bash scripts/vm-lab.sh helm list -A
```

### Administración Linux: entrar por SSH

```bash
# Mac, desde la raíz del repositorio
bash scripts/vm-lab.sh node cp

# Ya en Ubuntu como vagrant: acceso administrativo a Kubernetes
kubectl get nodes

# Solo cuando necesites administrar el sistema:
sudo -i
systemctl status kubelet --no-pager
journalctl -u kubelet -n 30 --no-pager
crictl ps -a
ls /etc/kubernetes/manifests
```

Tras `sudo -i`, el primer `exit` vuelve a `vagrant` y el segundo sale de SSH al Mac. Abre otra pestaña del Mac y usa `node w1` o `node w2` para otro nodo: no encadenes SSH entre las VMs por suposición.

El control plane tiene kubeconfig para `vagrant` y `root`. **Los workers no tienen credenciales administrativas por defecto.** Ejecuta `kubectl drain`/`uncordon` desde el control plane o desde el shell del Mac; `apt` y `systemctl`, en el nodo que estés manteniendo. Helm está disponible en el Mac, no se preinstala en las VMs.

El namespace que selecciones en el Mac no cambia el de `vagrant` o `root` en Ubuntu: son kubeconfigs distintos. Comprueba el destino o usa `-n` explícitamente.

## 4. Tu primera práctica completa

Haz este ejemplo en el **shell del Mac**, sin `sudo`. Usa un namespace exclusivo y conserva los manifiestos:

```bash
bash scripts/vm-lab.sh shell
mkdir -p .lab/answers/day-01
k create namespace exercise-student-01

k -n exercise-student-01 create deployment web \
  --image=nginx:1.28 --replicas=2 $do > .lab/answers/day-01/deploy.yaml
vim .lab/answers/day-01/deploy.yaml
k -n exercise-student-01 apply --dry-run=server -f .lab/answers/day-01/deploy.yaml
k -n exercise-student-01 apply -f .lab/answers/day-01/deploy.yaml
k -n exercise-student-01 rollout status deployment/web --timeout=120s

k -n exercise-student-01 expose deployment web --port=80 --target-port=80 \
  $do > .lab/answers/day-01/service.yaml
k -n exercise-student-01 apply -f .lab/answers/day-01/service.yaml
k -n exercise-student-01 get pods,service -o wide
k -n exercise-student-01 port-forward service/web 8080:80 --address 127.0.0.1
```

El último comando **se queda abierto**: es normal. En otra terminal del **Mac**:

```bash
curl http://127.0.0.1:8080/
```

Debes recibir la página de bienvenida de nginx. `Ctrl+C` en la terminal del port-forward cierra el túnel, no borra la aplicación. Si el puerto 8080 está ocupado, usa `8081:80` y consulta `http://127.0.0.1:8081/`.

Para repetir **solo este ejemplo**, después de guardar tus archivos:

```bash
# BORRA todos los recursos de este namespace, no el cluster
bash scripts/vm-lab.sh kubectl delete namespace exercise-student-01
```

El mensaje de `apply` no demuestra que una tarea esté resuelta: verifica réplicas, Ready, configuración y tráfico según el enunciado. En un ejercicio real utiliza sus nombres, imágenes, puertos y restricciones, no los de esta demostración.

## 5. Dónde guardar las respuestas

| Ubicación | ¿Sobrevive a `stop`/`start`? | ¿Sobrevive a `reset`? |
| --- | --- | --- |
| `.lab/answers/` en el Mac | Sí | **Sí** |
| Archivos dentro de Ubuntu | Sí | **No** |
| Pods, Secrets, PVC y datos del cluster | Se conservan los discos; las aplicaciones deben tolerar el reinicio | **No** |
| Historial/comandos recordados | No son un respaldo de tus soluciones | No dependas de ellos |

**No existe una carpeta compartida automática.** El mismo nombre de archivo en el Mac y en Ubuntu puede referirse a archivos diferentes. `.lab/` está excluido de Git; no fuerces su publicación. Tampoco es un respaldo frente a perder el Mac.

Si trabajas por SSH, como usuario `vagrant`, guarda tus manifiestos en una carpeta propia:

```bash
# Dentro de controlplane, como vagrant, NO después de sudo -i
mkdir -p ~/answers/day-01
kubectl run web --image=nginx:1.28 --dry-run=client -o yaml \
  > ~/answers/day-01/pod.yaml
```

Para copiarlos al **Mac**, abre otra terminal en la raíz del repositorio. Esta consulta de Vagrant usa explícitamente el mismo estado aislado; no crea VMs:

```bash
umask 077
VAGRANT_CWD="$PWD/lab/vms" VAGRANT_DOTFILE_PATH="$PWD/.lab/vms/vagrant" \
  vagrant ssh-config > .lab/vms/ssh-config
mkdir -p .lab/answers/day-01/from-controlplane
scp -F .lab/vms/ssh-config \
  controlplane:/home/vagrant/answers/day-01/pod.yaml \
  .lab/answers/day-01/from-controlplane/pod.yaml
```

Usa `node01` o `node02` como origen si el archivo está allí. Regenera `ssh-config` tras recrear las VMs, porque cambian claves y pueden cambiar puertos. No copies kubeconfigs, certificados, tokens ni snapshots sensibles como si fueran respuestas publicables. `kubectl cp` copia archivos de **Pods**, no de las VMs.

## 6. Moverte por los ejercicios

Lee primero el enunciado en `exercises/NN-nombre/README.md`; abre la solución solo al corregir. Guarda el tiempo, tus manifiestos y la comprobación del resultado.

| Si el enunciado habla de… | Dónde trabajas / adaptación local |
| --- | --- |
| Pods, RBAC, Services, NetworkPolicy, PV/PVC | `kubectl` desde el Mac o el control plane |
| Helm / Kustomize | Shell del Mac; `helm` / `kubectl apply -k` |
| kubelet, runtime, red del nodo, logs Linux | `node cp`, `w1` o `w2`, según el nodo afectado |
| etcd, API server, certificados, static Pods | `node cp`; confirmar rutas antes de editar |
| Ingress / Gateway API | Clases `traefik`; comprobar tráfico con el Host de la ruta |
| StorageClass | `standard`; almacenamiento local, no compartido entre nodos |
| Upgrade | [Práctica 1.34 → 1.35](vms/upgrade.md); no actualices todos los nodos a la vez |
| Instalación desde cero / CRI / CNI | [Modo bare](#8-recuperarte-de-prácticas-destructivas), con pérdida de las VMs actuales |

Los nombres del enunciado pueden ser distintos: en el lab usa `controlplane`, `node01`, `node02`. No cambies los nombres exigidos de recursos por comodidad en un simulacro o examen. En Apple Silicon, descarga binarios **Linux arm64** para Ubuntu; no Darwin ni amd64.

## 7. Terminar el día sin perder el trabajo

Guarda los archivos, copia al Mac los que quieras conservar y sal de los shells root/SSH. Desde la terminal normal del **Mac**:

```bash
cd "$HOME/Desarrollo/CKA-Certified-Kubernetes-Administrator"
bash scripts/vm-lab.sh stop
```

Esto apaga solo las tres VMs y libera recursos; no borra sus discos. Mañana usa `start`. Cerrar Terminal o salir con `exit` **no** apaga el laboratorio. No necesitas `down` ni `reset` para acabar una sesión.

## 8. Recuperarte de prácticas destructivas

Primero decide qué quieres recuperar:

| Situación | Acción |
| --- | --- |
| Solo quiero repetir un ejercicio de recursos | Limpiar únicamente sus recursos/namespace, tras guardar respuestas |
| Lab apagado | `start` |
| Quiero aprender a reparar la avería | Diagnosticar por SSH; no ejecutar `up`/`addons` para ocultarla |
| Quiero volver a un cluster limpio 1.34 | `reset full --yes` |
| Quiero instalar cluster/CRI/CNI desde cero | `reset bare --yes` |

**Los dos resets borran las tres VMs y todos sus datos.** No se ejecutan sin `--yes`; guarda antes las respuestas en el Mac. Funcionan incluso con la API rota, siempre que Vagrant y VirtualBox puedan gestionar las máquinas.

```bash
# Mac: cluster completo 1.34, complementos y comprobación funcional
bash scripts/vm-lab.sh reset full --yes

# ALTERNATIVA: Ubuntu + paquetes, SIN init/join ni CNI
bash scripts/vm-lab.sh reset bare --yes
```

Son **alternativas**, no pasos consecutivos. `bare` no debe pasar todavía `check`: no hay cluster. Sigue la [instalación manual](vms/README.md#todos-los-ejercicios-con-sus-prerrequisitos). No instales un segundo CNI sobre uno existente.

Si se interrumpe una reconstrucción, continúa con `up` para full o `machines` para bare; repetir `reset` destruiría lo ya creado. La recuperación requiere tiempo y conexión para descargar paquetes/imágenes. `down --yes` solo borra las VMs: no las reconstruye.

## 9. Si algo no funciona

| Síntoma | Primera comprobación |
| --- | --- |
| `No such file or directory` al invocar el script | Estás en el directorio equivocado o dentro de Ubuntu; vuelve al Mac y a la raíz del repositorio |
| `No hay VMs registradas` | Aún no hay instalación para ese checkout; `doctor` y `up` |
| API rechaza conexión después de apagar | `start`, esperar y consultar `status` |
| `kubectl` funciona en el Mac, no en un worker | El worker no tiene kubeconfig administrativo; es intencionado |
| `k: command not found` | No estás en un shell configurado; usa `kubectl` o entra con `shell` |
| `systemctl`/`apt` no existen | Estás en macOS; entra con `node` |
| `Pending` / `ImagePullBackOff` | `describe pod`: eventos, requests, PVC, imagen y conectividad al registro |
| `check` falla tras un ejercicio | Revisar cordon, métricas, CNI y rutas; no significa necesariamente que haya que resetear |
| `up`/`addons` deshace un cambio de práctica | No son comprobaciones de estado; `addons` reconcilia componentes |

`check` crea un namespace temporal y lo elimina al terminar, también ante fallos. No borra tus namespaces de ejercicios, pero consume recursos y requiere el cluster completo operativo.

**Hábito de estudiante:** host → contexto/namespace → cambio mínimo → comprobar el requisito → guardar → salir. Esta guía, las chuletas y Copilot son herramientas de preparación, no material permitido durante el examen.
