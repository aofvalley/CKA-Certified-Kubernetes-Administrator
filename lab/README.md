# Laboratorio kind: alternativa opcional

**Para estudiar con las VMs, vuelve a [la rutina única del README](../README.md#rutina-diaria).** El orden de trabajo está en [ejercicios por día](../exercises/README.md#ejercicios-por-día) y los comandos en [la chuleta unificada](../cheatsheet/cka-cheatsheet.md).

Esta página conserva exclusivamente la referencia del entorno Docker/kind y la validación técnica del laboratorio. **No necesitas instalar ni arrancar kind para seguir la rutina principal.** La instalación y recuperación de las VMs se documentan en [vms/README.md](vms/README.md).

## Alternativa Docker: entrar y trabajar con kind

Desde la raíz del repositorio, con Docker en marcha:

```bash
bash scripts/lab.sh up       # Primera instalación; reutiliza el cluster si existe
bash scripts/lab.sh check    # Comprobación funcional, con limpieza automática
bash scripts/lab.sh shell    # Sesión Bash de práctica
```

Dentro de esa sesión:

```bash
k config current-context    # kind-cka-10days
k get nodes                # Un control plane y dos workers
k top nodes
mkdir -p .lab/answers/day-01
```

`exit` devuelve a tu terminal habitual. Los aliases, el autocompletado y la configuración Vim se cargan **solo en esa sesión**; no se modifica `~/.vimrc`, `~/.zshrc`, `~/.bashrc` ni `~/.kube/config`.

También puedes ejecutar comandos sin entrar:

```bash
bash scripts/lab.sh kubectl get pods -A
bash scripts/lab.sh helm list -A
bash scripts/lab.sh status
bash scripts/lab.sh doctor
```

El kubeconfig administrativo se guarda con permisos `600` en `.lab/kubeconfig`. `.lab/` está excluido de Git y contiene también tus respuestas e historial. No publiques esa carpeta ni uses `git add -f` sobre ella. Los scripts fijan explícitamente el contexto del laboratorio; fuera de la sesión de práctica, tu `kubectl` normal sigue usando su configuración habitual.

## Qué queda instalado en la alternativa kind

| Componente | Versión / configuración | Prácticas |
| --- | --- | --- |
| kind | Requiere 0.32 o posterior | Cluster local desechable en Docker |
| Kubernetes | 1.35.5, imagen fijada por digest, ARM64/AMD64 | Un control plane + dos workers |
| Calico / Tigera Operator | 3.32.2; VXLAN, sin BGP | NetworkPolicy, comunicación entre nodos, CRDs y operador |
| Metrics Server | 0.9.0 | `kubectl top`, HPA y diagnóstico de recursos |
| Traefik | Chart 41.5.0 / aplicación 3.7.13 | IngressClass y GatewayClass `traefik` |
| Gateway API | CRDs estándar 1.6.1 | Gateway y HTTPRoute con tráfico real |
| local-path-provisioner | Incluido en la imagen kind | StorageClass `standard`, PVC dinámicos y WaitForFirstConsumer |

La API escucha en loopback (`127.0.0.1`); no hay puertos publicados en toda la LAN. Traefik usa un Service ClusterIP. Para acceder desde macOS:

```bash
# Dentro de la sesión del laboratorio; dejar abierto en esa terminal
k -n traefik port-forward service/traefik 8080:80 --address 127.0.0.1
# En otra terminal, tras crear una ruta con este hostname:
curl -H 'Host: app.cka.test' http://127.0.0.1:8080/
```

En los ejercicios 15 y 19 usa **`traefik`**, no `eg` ni `nginx`, como clase. El listener HTTP del Gateway puede usar el puerto **80**. No se crean Gateways de ejercicios de antemano: debes practicarlos tú. Las IP ClusterIP y de nodos no son directamente accesibles desde macOS con Docker Desktop; usa `port-forward` o un Pod cliente. Un Service `LoadBalancer` no obtiene una IP externa automáticamente.

**Solo para este laboratorio:** Metrics Server usa `--kubelet-insecure-tls` porque los certificados de kubelet de kind no tienen la validación de una instalación de producción. No copies esa excepción a clusters reales. Los nodos kind son contenedores privilegiados y comparten la VM de Docker; no ejecutes imágenes o scripts desconocidos.

### Requisitos y recursos

Docker local, kind >= 0.32, kubectl compatible con Kubernetes 1.35 (diferencia máxima de una minor), Helm 3, curl, Bash y conexión a los registros de imágenes. En este Mac ARM64 se usan imágenes multi-arquitectura.

Asigna al menos **6 GB a Docker; 8 GB recomendado**, unos 4 CPU y 12–15 GB de disco libre para imágenes. Con 24 GB de RAM en el Mac, evita levantar otros clusters pesados a la vez. No necesitas servicios cloud ni nuevas suscripciones. Si Docker está parado, `docker desktop start` lo inicia en macOS.

La primera descarga puede tardar varios minutos. `up` instala versiones fijadas y espera al CNI antes de exigir nodos Ready. Si falla una descarga, corrige la conectividad y repite `up`: no borra tus ejercicios. **Sí reconcilia los complementos**, por lo que puede deshacer cambios de práctica sobre Calico, Traefik o Metrics Server; no lo uses como comprobación diaria, usa `status`.

## Comprobación funcional

`bash scripts/lab.sh check` crea un namespace temporal único y comprueba:

- Tres nodos Ready; DNS y tráfico HTTP entre los dos workers.
- PVC dinámico Bound, escritura en el volumen y lectura desde HTTP.
- Un cliente permitido y otro bloqueado por NetworkPolicy, después de comprobar que ambos funcionaban sin ella. Un error de DNS/API no cuenta como bloqueo correcto.
- Gateway Programmed, HTTPRoute Accepted/ResolvedRefs e Ingress con tráfico HTTP real.
- Métricas de los tres nodos y un HPA capaz de obtener métricas.

Se elimina únicamente ese namespace temporal al terminar, también ante fallos; se imprimen diagnósticos antes de limpiarlo. No se limpian namespaces `exercise-*`. La prueba necesita los workers sin cordon y los complementos operativos.

## Operación diaria y recuperación

```bash
bash scripts/lab.sh node cp  # Bash Linux dentro del control plane
bash scripts/lab.sh node w1  # Primer worker
bash scripts/lab.sh node w2  # Segundo worker
```

Dentro de un nodo puedes estudiar `systemctl status kubelet`, `journalctl -u kubelet`, `crictl ps -a` y los manifiestos de `/etc/kubernetes/manifests` del control plane. Para kubectl dentro del control plane usa `export KUBECONFIG=/etc/kubernetes/admin.conf`. Los workers no tienen por defecto credenciales administrativas. Usa `exit` para volver y nunca ejecutes comandos `apt`/`systemctl` del ejercicio sobre macOS.

Para recuperar ejercicios habituales, elimina **solo** su namespace y repítelos. No guardes copias de manifiestos estáticos en `/etc/kubernetes/manifests`: kubelet también puede leer esas copias.

```bash
# BORRA exclusivamente el cluster cka-10days y sus volúmenes:
bash scripts/lab.sh down --yes
bash scripts/lab.sh up
```

Tus respuestas en `.lab/answers/` se conservan; los datos de PVC dentro de los nodos se pierden. No uses `docker system prune` ni borres otros clusters. Cerrar la terminal no borra el laboratorio; parar Docker pausa su disponibilidad.

## Limitaciones de la alternativa kind

Esta tabla describe **solo kind**, no el laboratorio principal de VMs. No es la distribución recomendada del plan de estudio; con las VMs se practican también las tareas de sistema.

| Ejercicios del repositorio | Entorno y adaptación |
| --- | --- |
| 01–08, 12–17, 19–25, 28 | Este laboratorio; sustituye nombres de nodos, clases y namespaces según corresponda |
| 10, 11, 17, 29 | kind permite inspeccionar/fallar/reparar componentes; entra con `node`, no con SSH. Guarda copias fuera de la carpeta de manifiestos |
| 09: actualización kubeadm | **VMs Linux o simulador**; los binarios de kind no siguen el ciclo de paquetes apt del ejercicio |
| 18 y 26: instalar CRI-dockerd | **VMs Linux desechables o simulador**; este cluster ya usa containerd, no sustituyas su runtime |
| 27: instalación de CNI | Estudia el operador aquí, pero ensaya la instalación desde cero en otro cluster sin CNI; no instales un segundo CNI sobre Calico |
| 30: TLS del control plane | Adaptar a los manifiestos y certificados reales del nodo; reservar pruebas destructivas para simulador/cluster desechable |
| 31: Argo CD | Opcional tras cubrir el temario esencial; útil para operadores/CRDs, no priorices una aplicación concreta sobre los dominios oficiales |

En la ruta principal las prácticas de sistema se realizan en las [VMs locales](vms/README.md). Conserva el **simulador incluido en tu inscripción**, si tu modalidad lo incluye, para practicar bajo tiempo y con el flujo del examen. La ficha oficial describe dos intentos, de 36 horas cada uno desde su activación. Comprueba tus derechos y no actives una sesión hasta disponer de tiempo para aprovecharla.

kind **no equivale al examen completo**: faltan instalación de máquinas desde cero, gestión real de paquetes, un control plane HA y el flujo SSH del escritorio remoto. Tampoco es almacenamiento CSI de producción: `standard` usa volúmenes locales. Debes comprender CNI/CSI/CRI, HA, `kubeadm init/join/upgrade`, copias/restauración de etcd y diagnóstico Linux, aunque algunas prácticas se hagan fuera.

## Validar cambios al laboratorio

Sin tocar el cluster:

```bash
python3 -m venv .lab/venv
.lab/venv/bin/python -m pip install -r lab/requirements-dev.txt
.lab/venv/bin/python -m unittest discover -s lab/tests -v
for script in scripts/lab.sh scripts/vm-lab.sh scripts/check-lab.sh scripts/exam-setup.sh lab/bashrc lab/vms/bootstrap.sh lab/vms/init.sh; do
  bash -n "$script" || break
done
```

Las pruebas locales cubren el aislamiento, las protecciones del CLI y la sintaxis/configuración YAML; `vm-lab.sh check` cubre las VMs y el comportamiento real del cluster (`lab.sh check` sigue disponible para kind).
