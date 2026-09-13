# Banco de ejercicios CKA

Los 31 enunciados están aquí, agrupados en los cinco dominios CKA. **No hace falta recorrer este índice para decidir por dónde empezar:** usa la [rutina diaria](../README.md#rutina-diaria) y el [orden por día](#ejercicios-por-día). Hoy, empieza por [01 — Pod básico](01-pod-basics/README.md#tasks).

En cada archivo, lee `Tasks`; consulta `Hints` solo si te atascas y abre `Solution` al corregir. La [chuleta única](../cheatsheet/cka-cheatsheet.md#4-creación-imperativa) sirve para elegir el generador o cambio rápido, no para pegar una solución completa.

## Ejercicios por día

| Día | Trabajo, en orden |
| --- | --- |
| 01 | [Pod](01-pod-basics/README.md#tasks) → [ConfigMap/Secret](03-configmap-secret/README.md#tasks) → [Deployment](06-deployment-rollout/README.md#tasks) |
| 02 | Services/DNS → [NetworkPolicy](05-networkpolicy/README.md#tasks) → [políticas complejas](28-network-policy-complex/README.md#tasks) → [Ingress](19-ingress-classic/README.md#tasks) |
| 03 | [RBAC](04-rbac/README.md#tasks) → [drain](08-node-drain-cordon/README.md#tasks) → [recursos](23-resource-requests-tuning/README.md#tasks) → [seguridad](20-pod-security-standards/README.md#tasks) → [prioridad](24-priorityclass-patch/README.md#tasks) |
| 04 | [PV/PVC](12-storage-pv-pvc/README.md#tasks) → [binding](25-storage-waitforfirstconsumer/README.md#tasks) → [StatefulSet](07-statefulset/README.md#tasks) → [HPA](16-hpa/README.md#tasks-hpa) |
| 05 | [Static Pod](10-static-pod/README.md#tasks) → [diagnóstico](11-troubleshoot-cluster/README.md#tasks) → [debug](17-kubectl-debug/README.md#tasks) → [etcd endpoint](29-troubleshoot-etcd-endpoint/README.md#tasks) |
| 06 | [Backup/restore etcd](../cheatsheet/cka-cheatsheet.md#12-etcd-backup-y-restore) → [upgrade](../lab/vms/upgrade.md) → [TLS](30-tls-configuration-update/README.md#tasks) |
| 07 | [Helm](13-helm-install-upgrade/README.md#tasks) → [Kustomize](14-kustomize-overlays/README.md#tasks) → [Gateway](15-gateway-api/README.md#tasks) → simulador 1, si lo tienes incluido |
| 08 | [Instalación manual y CNI](../lab/vms/README.md#todos-los-ejercicios-con-sus-prerrequisitos) → [Mock 01](../mock-exams/MOCK-EXAM-01.md) |
| 09 | Simulador 2 y repetir los tres fallos principales |
| 10 | Repetir errores conocidos y descansar |

Las prácticas de sistema afectan al cluster completo. Antes de restaurar etcd o reconstruir VMs, [guarda las respuestas fuera de ellas](../lab/vms/README.md#guardar-respuestas-en-el-mac). El mock necesita preparar sus prerrequisitos: el temporizador no despliega el escenario.

## Todos los enunciados

| # | Exercise | Domain | Difficulty | Time |
|---|---|---|---|---|
| 01 | [Pod Basics](01-pod-basics/) | Workloads & Scheduling | Easy | 10 min |
| 02 | [Multi-Container Pod](02-multi-container-pod/) | Workloads & Scheduling | Medium | 15 min |
| 03 | [ConfigMap & Secret](03-configmap-secret/) | Workloads & Scheduling | Easy | 10 min |
| 04 | [RBAC](04-rbac/) | Cluster Architecture | Medium | 15 min |
| 05 | [NetworkPolicy](05-networkpolicy/) | Services & Networking | Medium | 20 min |
| 06 | [Deployment Rollout](06-deployment-rollout/) | Workloads & Scheduling | Easy | 10 min |
| 07 | [StatefulSet](07-statefulset/) | Workloads & Scheduling | Medium | 15 min |
| 08 | [Node Drain & Cordon](08-node-drain-cordon/) | Cluster Architecture | Easy | 10 min |
| 09 | [kubeadm Upgrade](09-kubeadm-upgrade/) | Cluster Architecture | Hard | 25 min |
| 10 | [Static Pod](10-static-pod/) | Workloads & Scheduling | Easy | 10 min |
| 11 | [Troubleshoot Cluster](11-troubleshoot-cluster/) | Troubleshooting | Hard | 25 min |
| 12 | [Storage — PV & PVC](12-storage-pv-pvc/) | Storage | Medium | 15 min |
| 13 | [Helm Install & Upgrade](13-helm-install-upgrade/) | Cluster Architecture | Medium | 15 min |
| 14 | [Kustomize Overlays](14-kustomize-overlays/) | Cluster Architecture | Medium | 15 min |
| 15 | [Gateway API](15-gateway-api/) | Services & Networking | Medium | 20 min |
| 16 | [Horizontal Pod Autoscaler](16-hpa/) | Workloads & Scheduling | Medium | 15 min |
| 17 | [kubectl debug](17-kubectl-debug/) | Troubleshooting | Medium | 15 min |
| 18 | [CRI-dockerd Setup](18-cri-dockerd-setup/) | Cluster Architecture | Medium | 15 min |
| 19 | [Classic Ingress](19-ingress-classic/) | Services & Networking | Medium | 15 min |
| 20 | [Pod Security Standards](20-pod-security-standards/) | Cluster Architecture | Medium | 15 min |
| 21 | [Jobs & CronJobs](21-jobs-cronjobs/) | Workloads & Scheduling | Medium | 15 min |
| 22 | [PriorityClass](22-priorityclass/) | Workloads & Scheduling | Medium | 15 min |
| 23 | [Resource Requests Tuning](23-resource-requests-tuning/) | Workloads & Scheduling | Hard | 20 min |
| 24 | [PriorityClass Patch](24-priorityclass-patch/) | Workloads & Scheduling | Medium | 15 min |
| 25 | [Storage WaitForFirstConsumer](25-storage-waitforfirstconsumer/) | Storage | Hard | 20 min |
| 26 | [CRI-dockerd Installation](26-cri-dockerd-setup/) | Cluster Architecture | Hard | 30 min |
| 27 | [CNI Tigera/Calico Install](27-cni-tigera-install/) | Services & Networking | Hard | 30 min |
| 28 | [Complex NetworkPolicy](28-network-policy-complex/) | Services & Networking | Hard | 25 min |
| 29 | [Troubleshoot etcd Endpoint](29-troubleshoot-etcd-endpoint/) | Troubleshooting | Hard | 20 min |
| 30 | [TLS Configuration Update](30-tls-configuration-update/) | Security | Hard | 20 min |
| 31 | [Argo CD GitOps Setup](31-argocd-gitops-setup/) | Cluster Architecture | Hard | 25 min |

| Domain | Weight | Exercises |
|---|---|---|
| Troubleshooting | 30% | 11, 17, 29 |
| Cluster Architecture | 25% | 04, 08, 09, 13, 14, 18, 20, 26, 31 |
| Services & Networking | 20% | 05, 15, 19, 27, 28 |
| Workloads & Scheduling | 15% | 01, 02, 03, 06, 07, 10, 16, 21, 22, 23, 24 |
| Storage | 10% | 12, 25 |

## Namespaces y respuestas

Para práctica diaria de un solo namespace, adapta el namespace del enunciado al del día, también en YAML, referencias RBAC y DNS, como explica [la rutina](../README.md#4-hacer-un-ejercicio-no-copiar-una-solución). Si pide varios namespaces, no los fusiones. En simulacros/examen conserva los nombres exactos exigidos.

Guarda cada ejercicio en su subcarpeta dentro de `~/answers/cka-dia-NN/` en `controlplane`. **No ejecutes `Cleanup` al terminar el día** si quieres conservar los objetos: `stop` apaga sin borrar. Limpia deliberadamente solo los recursos del ejercicio cuando quieras repetirlo; los recursos globales no se aíslan por namespace.

Las tareas de sistema necesitan preparar sus prerrequisitos. Nodos, clases y versiones del lab se consultan en [la referencia técnica de VMs](../lab/vms/README.md#todos-los-ejercicios-con-sus-prerrequisitos); no ejecutes comandos Linux en el Mac.
