# Laboratorio CKA y preparación intensiva: 13–22 de septiembre de 2026

**Examen: 23 de septiembre.** Esta ruta presupone unas **3,5–4 horas diarias** y conocimientos básicos de Linux. Diez días pueden servir para consolidar conocimientos, pero no garantizan aprobar desde cero: el diagnóstico del primer día marca el ritmo.

La [ficha oficial CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) y las [instrucciones oficiales](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) consultadas el 13/09/2026 indican Kubernetes **1.35**, **dos horas** y 15–20 tareas. La [FAQ oficial](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks) exige **66 %** para aprobar. Los pesos son por dominio, no por ejercicio; no interpretes «10 de 15 preguntas» del repositorio como equivalencia oficial.

Revisa otra vez la versión y las reglas en tu portal antes del examen: pueden cambiar. La documentación oficial prevalece sobre las notas y soluciones del repositorio.

**Referencia rápida:** [chuleta CKA en español](../cheatsheet/cka-cheatsheet-es.md), con comandos, verificaciones y errores típicos. Úsala para practicar, no como material de consulta durante el examen.

## Entrar y trabajar

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

## Qué queda instalado

| Componente | Versión / configuración | Prácticas |
|---|---|---|
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

## Qué practicar aquí y qué requiere otro entorno

| Ejercicios del repositorio | Entorno y adaptación |
|---|---|
| 01–08, 12–17, 19–25, 28 | Este laboratorio; sustituye nombres de nodos, clases y namespaces según corresponda |
| 10, 11, 17, 29 | kind permite inspeccionar/fallar/reparar componentes; entra con `node`, no con SSH. Guarda copias fuera de la carpeta de manifiestos |
| 09: actualización kubeadm | **VMs Linux o simulador**; los binarios de kind no siguen el ciclo de paquetes apt del ejercicio |
| 18 y 26: instalar CRI-dockerd | **VMs Linux desechables o simulador**; este cluster ya usa containerd, no sustituyas su runtime |
| 27: instalación de CNI | Estudia el operador aquí, pero ensaya la instalación desde cero en otro cluster sin CNI; no instales un segundo CNI sobre Calico |
| 30: TLS del control plane | Adaptar a los manifiestos y certificados reales del nodo; reservar pruebas destructivas para simulador/cluster desechable |
| 31: Argo CD | Opcional tras cubrir el temario esencial; útil para operadores/CRDs, no priorices una aplicación concreta sobre los dominios oficiales |

No instalamos VMs adicionales: para las prácticas de sistema usa primero el **simulador incluido en tu inscripción**, si tu modalidad lo incluye. La ficha oficial describe dos intentos, de 36 horas cada uno desde su activación. Comprueba tus derechos y no actives una sesión hasta disponer de tiempo para aprovecharla.

kind **no equivale al examen completo**: faltan instalación de máquinas desde cero, gestión real de paquetes, un control plane HA y el flujo SSH del escritorio remoto. Tampoco es almacenamiento CSI de producción: `standard` usa volúmenes locales. Debes comprender CNI/CSI/CRI, HA, `kubeadm init/join/upgrade`, copias/restauración de etcd y diagnóstico Linux, aunque algunas prácticas se hagan fuera.

## Ruta de diez días

Pesos oficiales: **troubleshooting 30 %, arquitectura/instalación/configuración 25 %, redes 20 %, workloads/scheduling 15 %, almacenamiento 10 %**. Dedica el 70–80 % del tiempo al teclado, no a leer todo el README.

| Día | Fecha | Trabajo principal | Evidencia de avance |
|---|---|---|---|
| 1 | 13 sep | Diagnóstico de abajo; ejercicios 01, 03 y 06. Pods, YAML, namespaces, ConfigMap/Secret y rollout | Crear/verificar/reparar una aplicación sin copiar soluciones |
| 2 | 14 sep | 05 y 28; Services, EndpointSlices, DNS/CoreDNS y NetworkPolicy. Añadir avería de selector/puerto | Demostrar conexiones permitidas y denegadas; localizar el fallo con evidencia |
| 3 | 15 sep | 04, 08, 20, 22–24; RBAC, ServiceAccounts, drain/cordon, requests/limits, taints y affinity | Verificar permisos con `auth can-i` y recuperar un Pod Pending |
| 4 | 16 sep | 07, 12, 25 y 16; PV/PVC, reclaim policy, WaitForFirstConsumer, StatefulSet y HPA | Explicar por qué un PVC espera y demostrar que conserva datos al recrear un Pod |
| 5 | 17 sep | 10, 11, 17 y 29; kubelet, runtime, logs, static Pods, API server y etcd | Resolver tres fallos en menos de 15 min cada uno; guardar/restaurar configuración |
| 6 | 18 sep | Instalación/upgrade con kubeadm, CRI/CNI/CSI y HA; **simulador 1: 120 min**, después revisión | Ejecutar tareas Linux en entorno apropiado y clasificar los fallos del simulador |
| 7 | 19 sep | 13, 14, 15 y 19; Helm, Kustomize, Ingress y Gateway API. Inspeccionar CRDs/operador Calico | Instalar/actualizar un chart y servir HTTP por Ingress y HTTPRoute; corregir simulador 1 |
| 8 | 20 sep | **Simulador 2: 120 min**, sin ayuda; 90 min de corrección y repetición | Priorizar por puntos/tiempo, conservar 15–20 min para verificación |
| 9 | 21 sep | [Mock 01](../mock-exams/MOCK-EXAM-01.md) o [Mock 02](../mock-exams/MOCK-EXAM-02.md), el no practicado, 120 min; reforzar los tres puntos débiles | Objetivo orientativo ≥80 % de los puntos practicables, sin soluciones y dentro de tiempo |
| 10 | 22 sep | Repaso ligero de errores, documentación, comandos y estrategia; revisión PSI, documento de identidad y hora/zona del examen | Dos o tres tareas conocidas sin atascarte; descansar, no abrir temas grandes |

En los mocks del repositorio prepara los prerrequisitos que pide cada enunciado: el temporizador **no despliega averías ni configura máquinas**. Las tareas de VMs se hacen en el simulador o se marcan «no practicadas», nunca como aprobadas. El runner solo presenta un extracto inicial: mantén abierto el archivo completo de preguntas. Usa las soluciones únicamente al corregir; no confundas una puntuación parcial local con una predicción oficial.

Bloque diario normal: **20 min** de repetición sin apuntes, **100 min** de ejercicios, **45 min** de troubleshooting, **35 min** de tareas cronometradas y **20 min** para explicar errores y repetirlos. En días de simulador sustituye ese bloque por las dos horas de examen y la corrección.

Si dispones de menos tiempo, conserva troubleshooting + RBAC/kubeadm + redes, y reduce Argo CD, ejercicios duplicados y lectura larga. Si al final del día 3 sigues necesitando soluciones para tareas básicas, el calendario es de alto riesgo: revisa las opciones y plazos de reprogramación de tu inscripción.

## Primera sesión: diagnóstico de 45 minutos

Entra con `bash scripts/lab.sh shell`. Lee los enunciados de [01](../exercises/01-pod-basics/README.md), [03](../exercises/03-configmap-secret/README.md), [06](../exercises/06-deployment-rollout/README.md) y [04](../exercises/04-rbac/README.md), sin abrir sus soluciones.

| Minutos | Tarea | Criterio |
|---|---|---|
| 0–10 | Ejercicio 01 | Pod Running/Ready, salida y descripción verificadas |
| 10–20 | Ejercicio 03 | Aplicación recibe los valores del ConfigMap y Secret |
| 20–30 | Ejercicio 06 | Actualización y rollback con versión y réplicas verificadas |
| 30–45 | Ejercicio 04 | Identidad puede hacer lo solicitado y no lo que queda fuera |

Si te atascas más de ocho minutos, registra el síntoma y pasa a la siguiente tarea. Después corrige y repite desde cero. Guarda los manifiestos en `.lab/answers/day-01/` y usa este formato para trabajar conmigo durante la preparación:

```text
Día / ejercicio:
Tiempo:
Resultado esperado:
Resultado observado:
Comandos de verificación y salida relevante (sin secretos):
Pista que necesité:
Causa raíz y cómo la comprobé:
```

Considera dominada una tarea tras **dos resoluciones correctas sin ayuda**, en días distintos. En nuestras sesiones puedo dar primero una pista, después ayudarte a diagnosticar y finalmente revisar la solución. El objetivo no es memorizar YAML: es llegar al estado pedido y demostrarlo.

## Reglas para simulacros y examen

Usa solo los [recursos oficialmente permitidos](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed): documentación/blog Kubernetes, Helm, Gateway API para CKA y las referencias que proporcione cada tarea. Este repositorio, Copilot y otros asistentes son herramientas de **preparación**, no ayuda durante el examen.

Practica el flujo del entorno actual: leer el host asignado, entrar por SSH, comprobar contexto/namespace, resolver, verificar y salir antes de la siguiente tarea. No des por hecho que basta con cambiar el contexto. En el escritorio Linux, practica copiar/pegar con Ctrl+Shift+C/V y el manejo de Vim.

Objetivo de estrategia: primera pasada de tareas claras, segunda para las atascadas y 15–20 minutos finales para verificar. La referencia es el requisito observable de la tarea, no que `apply` haya terminado sin errores. Haz ya la [comprobación PSI](https://syscheck.bridge.psiexams.com/) y revisa identificación, monitor único, webcam y permisos del navegador; no dejes esa parte para el día 23.

## Validar cambios al laboratorio

Sin tocar el cluster:

```bash
python3 -m venv .lab/venv
.lab/venv/bin/python -m pip install -r lab/requirements-dev.txt
.lab/venv/bin/python -m unittest discover -s lab/tests -v
for script in scripts/lab.sh scripts/check-lab.sh scripts/exam-setup.sh lab/bashrc; do
  bash -n "$script" || break
done
```

Las pruebas locales cubren el aislamiento, las protecciones del CLI y la sintaxis/configuración YAML; `lab.sh check` cubre el comportamiento real del cluster.
