# CKA: practicar, no leer manuales

**Arrancar → entrar en Ubuntu → preparar el día → hacer un ejercicio → apagar.**

## Rutina diaria

### 1. Arrancar y entrar — en el Mac

```bash
cd "$HOME/Desarrollo/CKA-Certified-Kubernetes-Administrator"
bash scripts/vm-lab.sh start
bash scripts/vm-lab.sh node cp
```

Ya estás por SSH en `controlplane`. Para otro nodo: `node w1` o `node w2` desde otra terminal del Mac. Si todavía no tienes las VMs, consulta la [instalación](lab/vms/README.md#primera-instalación).

### 2. Preparar Bash — dentro de Ubuntu, una vez por terminal

```bash
alias k=kubectl
alias kn='kubectl config set-context --current --namespace'
export do='--dry-run=client -o yaml'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
hostname
k config get-contexts
k get nodes
```

Espera `controlplane`, contexto `kubernetes-admin@kubernetes` y tres nodos `Ready`. No necesitas `sudo -i`. En Vim: `:set et ts=2 sw=2 ai`.

### 3. Preparar o retomar el namespace del día

```bash
NS=cka-dia-01
k create namespace "$NS" $do | k apply -f -
kn "$NS"
mkdir -p "$HOME/answers/$NS" && cd "$HOME/answers/$NS"
k get pods
```

Repetirlo **no borra nada**. Otro día: cambia a `cka-dia-02`; para continuar lo anterior, reutiliza `cka-dia-01`.

### 4. Hacer un ejercicio, no copiar una solución

**Hoy: [01 — Pod básico](exercises/01-pod-basics/README.md#tasks).** Después, [03 — ConfigMap/Secret](exercises/03-configmap-secret/README.md#tasks) y [06 — Deployment](exercises/06-deployment-rollout/README.md#tasks).

Lee `Tasks` en el Mac y trabaja en SSH. Usa la **[chuleta imperativa](cheatsheet/cka-cheatsheet.md#4-creación-imperativa)** solo para lo que te falta:

- Crear algo sencillo: comando imperativo directo.
- Añadir campos o guardar un manifiesto: `$do > archivo.yaml`, editar y aplicar.
- Modificar: `set`, `scale`, `label` o `patch`, sin rehacer todo el YAML.

Escribe tú, verifica el resultado y repite cambiando algún requisito. Abre `Solution` **al corregir**, no al empezar. Guarda cada ejercicio en una subcarpeta del día para no sobrescribir archivos.

En prácticas de un solo namespace, sustituye el del enunciado por `$NS` en comandos, YAML y referencias. Si pide varios, mantenlos separados. En simulacros usa los nombres exactos. Nodos, PV y etcd no quedan aislados por namespace.

### 5. Guardar y apagar

Guarda en Vim con `Esc`, `:wq`. Ejecuta `exit` para volver al Mac; después:

```bash
bash scripts/vm-lab.sh stop
```

**Mañana repite 1–3.** `stop` conserva discos, objetos y tus YAML. No ejecutes `Cleanup`, `down` ni `reset` para terminar. El namespace no es un backup: antes de reconstruir las VMs, [copia tus respuestas al Mac](lab/vms/README.md#guardar-respuestas-en-el-mac).

**Cuando lo necesites:** [resto de ejercicios por día](exercises/README.md#ejercicios-por-día) · [problemas con las VMs](lab/vms/README.md#diagnóstico-de-acceso).
