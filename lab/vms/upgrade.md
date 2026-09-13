# Práctica real: Kubernetes 1.34.11 → 1.35.8

Esta práctica **no se ejecuta durante `up`**: el laboratorio queda en 1.34 para que hagas tú el upgrade. Sigue el [procedimiento oficial de kubeadm para 1.35](https://v1-35.docs.kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/). No saltes versiones minor. Las versiones aquí fijadas están disponibles en `pkgs.k8s.io`; usa las que pida el enunciado en el examen.

Abre una terminal SSH al control plane y otra al worker en mantenimiento. Los comandos `apt` y `systemctl` siguientes se ejecutan **dentro de Ubuntu**, nunca en macOS.

## 1. Estado inicial y respaldo

```bash
# Desde el Mac
bash scripts/vm-lab.sh node cp
sudo -i

# En controlplane
kubectl get nodes -o wide
kubectl get pods -A
kubeadm version -o short
apt-mark showhold
crictl ps
mkdir -p /root/cka-backup
cp -a /etc/kubernetes /root/cka-backup/kubernetes
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /root/cka-backup/etcd-before-upgrade.db
etcdutl snapshot status /root/cka-backup/etcd-before-upgrade.db -w table
```

Los certificados y el snapshot son sensibles: no los publiques ni los subas al repositorio. Un respaldo dentro de la VM **no sobrevive a `down`**. Practica por separado la restauración; no basta con tener un archivo. Para volver a la base de este laboratorio se recrean las VMs: Kubernetes no admite un downgrade general como reversión de un upgrade.

## 2. Actualizar kubeadm y el control plane

```bash
# En controlplane como root
sed -i 's@core:/stable:/v1.34/deb/@core:/stable:/v1.35/deb/@' \
  /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.8-1.1
apt-mark hold kubeadm
kubeadm version -o short
kubeadm upgrade plan
kubeadm upgrade apply v1.35.8
```

Lee el plan y confirma el upgrade interactivo. El control plane tiene una sola réplica: durante su reinicio puede interrumpirse el acceso a la API. kubeadm actualiza los componentes del control plane y, cuando corresponde, etcd, CoreDNS y kube-proxy; **no actualiza por ti los paquetes kubelet/kubectl**.

Calico 3.32.2 está configurado para esta práctica con 1.34 y 1.35. Comprueba su estado antes y después; no instales un segundo CNI para hacer el upgrade.

## 3. Actualizar kubelet y kubectl del control plane

```bash
# En controlplane como root
kubectl drain controlplane --ignore-daemonsets
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.8-1.1 kubectl=1.35.8-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
systemctl is-active kubelet
kubectl uncordon controlplane
kubectl wait --for=condition=Ready node/controlplane --timeout=180s
kubectl get nodes
```

## 4. Actualizar node01 y después node02

Desde el **control plane**:

```bash
kubectl drain node01 --ignore-daemonsets
```

Si drain se bloquea por un PodDisruptionBudget, Pods sin controlador o `emptyDir`, diagnostica el motivo. No añadas `--force` ni `--delete-emptydir-data` automáticamente: pueden perder datos o dejar Pods sin recrear.

Desde el **Mac**, en otra terminal:

```bash
bash scripts/vm-lab.sh node w1
sudo -i
```

Dentro de **node01**:

```bash
sed -i 's@core:/stable:/v1.34/deb/@core:/stable:/v1.35/deb/@' \
  /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.8-1.1
apt-mark hold kubeadm
kubeadm upgrade node
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.8-1.1 kubectl=1.35.8-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
systemctl is-active kubelet
```

De vuelta en el **control plane**:

```bash
kubectl uncordon node01
kubectl wait --for=condition=Ready node/node01 --timeout=180s
kubectl get nodes -o wide
```

Repite la misma secuencia para **node02** (`node w2`), cambiando el nombre en `drain`, `uncordon` y `wait`. No drenes los dos workers simultáneamente.

## 5. Verificar el resultado, no solo el comando

```bash
# En controlplane
kubectl get nodes -o wide
kubectl get pods -A
kubeadm version -o short
kubectl version

# En el Mac, después de salir de SSH
bash scripts/vm-lab.sh check
```

Resultado esperado: tres nodos **Ready en v1.35.8**, ninguno con SchedulingDisabled, kubeadm/kubelet/kubectl en la versión solicitada en cada nodo, CNI y CoreDNS operativos y comprobaciones funcionales correctas. Guarda el tiempo empleado y cualquier error; después repite desde una recreación del laboratorio sin mirar la solución.
