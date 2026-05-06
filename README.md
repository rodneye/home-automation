# k8s-home-automation

Kubernetes deployments for my home automation stack.

This repo contains setup notes and manifests for a small K3s home cluster running on Raspberry Pi / Debian nodes, with:

- K3s control-plane and worker nodes
- NFS-backed persistent storage
- Cloudflare Tunnel via `cloudflared`
- Traefik ingress

---

## Assumptions

This README assumes:

- Debian / Raspberry Pi OS Lite
- K3s is used as the Kubernetes distribution
- NFS is used for persistent Kubernetes storage
- The control-plane node IP is `192.168.88.213`
- The NFS server IP is `192.168.88.100`
- Worker nodes may optionally use Raspberry Pi overlay filesystem to reduce corruption risk after power loss

Adjust the values below for your environment.

---

## Cluster values

Example values used throughout this README:

```bash
export K3S_SERVER_IP="192.168.88.213"
export NFS_SERVER_IP="192.168.88.100"
export K3S_NODE_TOKEN="<replace-with-token-from-control-plane>"
export DOMAIN="ellishome.co.za"
export CLOUDFLARE_TUNNEL_NAME="my-tunnel"
```

NFS exports expected on the NFS server:

```text
/export/k8s-storage
```

---

# 1. Base setup for all nodes

Run this section on both the control-plane node and worker nodes.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl ca-certificates gnupg lsb-release nfs-common
```

---

# 2. Disable swap

Kubernetes expects swap to be disabled unless swap support has been explicitly configured.

Disable swap immediately:

```bash
sudo swapoff -a
```

Check what swap is active:

```bash
free -h
swapon --show
systemctl list-units --type=service | grep -Ei 'swap|zram' || true
systemctl list-unit-files | grep -Ei 'swap|zram' || true
```

## 2.1 Disable `dphys-swapfile`

Use this if the node has `dphys-swapfile`.

```bash
sudo systemctl stop dphys-swapfile || true
sudo systemctl disable dphys-swapfile || true

if [ -f /etc/dphys-swapfile ]; then
  sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=0/' /etc/dphys-swapfile
fi

sudo dphys-swapfile swapoff || true
sudo dphys-swapfile uninstall || true
```

## 2.2 Disable zram swap

Use this if `swapon --show` shows something like `/dev/zram0`.

```bash
sudo mkdir -p /etc/systemd/zram-generator.conf.d

sudo tee /etc/systemd/zram-generator.conf.d/disable-zram.conf >/dev/null <<'EOF'
[zram0]
zram-size = 0
EOF

sudo systemctl daemon-reload
```

Reboot after disabling swap:

```bash
sudo reboot
```

After reboot, confirm swap is disabled:

```bash
free -h
swapon --show
```

Expected result:

```text
Swap: 0B
```

`swapon --show` should return no rows.

---

# 3. Enable cgroups on Raspberry Pi

On Raspberry Pi nodes, K3s needs memory cgroups enabled.

Edit:

```bash
sudo vi /boot/firmware/cmdline.txt
```

Add this to the end of the existing single line:

```text
cgroup_memory=1 cgroup_enable=memory
```

The file must remain a single line.

Reboot:

```bash
sudo reboot
```

Verify after reboot:

```bash
cat /proc/cmdline
```

You should see:

```text
cgroup_memory=1 cgroup_enable=memory
```

---

# 4. Install NFS client and create mount folders

Run this on every node that needs NFS access.

```bash
sudo apt update
sudo apt install -y nfs-common

sudo mkdir -p /mnt/nfs-storage
sudo chown root:root /mnt/nfs-storage
sudo chmod 755 /mnt/nfs-storage
```

Check what the NFS server exports:

```bash
showmount -e 192.168.88.100
```

Expected exports:

```text
/export/k8s-storage
```

---

# 5. Configure NFS mounts

Edit `/etc/fstab`:

```bash
sudo vi /etc/fstab
```

Add these entries:

```fstab
192.168.88.100:/export/k8s-storage /mnt/nfs-storage nfs defaults,_netdev,vers=3,nolock,hard,intr,noatime,nodiratime,rsize=131072,wsize=131072,timeo=150,retrans=5 0 0
```

Reload systemd and mount everything:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

Verify:

```bash
findmnt | grep nfs
df -h | grep nfs
```

If the mount fails, check the latest kernel messages:

```bash
dmesg | tail -n 50
```

---

# 6. Install K3s control-plane node

Run this on the control-plane node only.

```bash
curl -sfL https://get.k3s.io | sh -
```

Check status:

```bash
sudo systemctl status k3s
kubectl get nodes -o wide
```

Get the node token for joining worker nodes:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Save this token somewhere safe.

Do not commit this token to GitHub.

---

# 7. Install K3s worker nodes

Run this on each worker node.

Set the required variables:

```bash
export K3S_SERVER_IP="192.168.88.213"
export K3S_NODE_TOKEN="<replace-with-token-from-control-plane>"
```

curl -sfL https://get.k3s.io | K3S_URL=https://192.168.88.213:6443 K3S_TOKEN=K3S_NODE_TOKEN sh -

# Install the K3s agent:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://${K3S_SERVER_IP}:6443 \
  K3S_TOKEN=${K3S_NODE_TOKEN} \
  sh -
```

### Check worker status:

```bash
sudo systemctl status k3s-agent
```

### From the control-plane node:

```bash
kubectl get nodes -o wide
```

---

# 8. Optional worker-node overlay filesystem

For SSD boot, sudden power loss can corrupt the boot or root filesystem.

On worker nodes only, consider enabling Raspberry Pi overlay filesystem after K3s is installed and confirmed working.

```bash
sudo raspi-config
```

Go to:

```text
Performance Options -> Overlay File System
```

Enable overlay and reboot.

Check if overlay is enabled:

```bash
findmnt /
```

If overlay is active, you should see something like:

```text
overlay on / type overlay
```

If overlay is disabled, you will see the real root device, for example:

```text
/dev/sda2 on / type ext4
```

Important notes:

- Only enable overlay on worker nodes.
- Do not blindly enable overlay on the control-plane node.
- Changes made after enabling overlay may not persist after reboot.
- NFS-backed app data will still persist because it lives off-node.
- Worker nodes can be treated as disposable if all app data is on NFS.

To disable overlay again:

```bash
sudo raspi-config
```

Then go to:

```text
Performance Options -> Overlay File System
```

Disable it and reboot.

---

# 9. Preserve source IP through Traefik

To preserve source IPs through Traefik, edit the Traefik service:

```bash
kubectl edit svc traefik -n kube-system
```

Set:

```yaml
externalTrafficPolicy: Local
```

Verify:

```bash
kubectl get svc traefik -n kube-system -o yaml | grep externalTrafficPolicy
```

---

# 10. Cloudflare Tunnel

## 10.1 Install `cloudflared`

```bash
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
  sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt update
sudo apt install -y cloudflared
```

## 10.2 Authenticate and create tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create my-tunnel
```

This creates a credentials JSON file under:

```text
~/.cloudflared/
```

## 10.3 Create Kubernetes secret

Replace `<TUNNEL_ID>` with the real tunnel credentials file name.

```bash
kubectl create secret generic tunnel-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL_ID>.json
```

## 10.4 Deploy cloudflared

```bash
kubectl apply -f cloudflared.yaml
```

## 10.5 Create DNS route

```bash
cloudflared tunnel route dns my-tunnel "*.ellishome.co.za"
```

---

# 11. NFS dynamic storage provisioner

Add the Helm repo if it has not already been added:

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update
```

Install or upgrade the provisioner:

```bash
helm upgrade --install nfs-client \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=192.168.88.100 \
  --set nfs.path=/export/k8s-storage \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true \
  --set nfs.mountOptions='{vers=3,nolock,hard,intr,rsize=131072,wsize=131072,tcp,actimeo=1,timeo=600,retrans=2}'
```

Verify:

```bash
kubectl get storageclass
kubectl get pods -A | grep nfs
```

---

# 12. Install Argo CD

Create the namespace and install Argo CD:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

If you want to manage Argo CD with Helm later, add the repo first:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

Apply the local config that allows the Argo CD server to run insecure behind Traefik:

```bash
kubectl apply -f argocd/configmap.yaml
kubectl -n argocd rollout restart deployment argocd-server
```

Apply the ingress:

```bash
kubectl apply -n argocd -f argocd/argocd-ingress.yaml
```

The ingress manifest currently uses:

```text
argocd.ellishome.co.za
```

Update `argocd/argocd-ingress.yaml` if your domain is different.

If you prefer Helm for updating the server params, you can also run:

```bash
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --reuse-values \
  --set configs.params."server.insecure"="true"
```

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo
```

---

# 13. Quick setup commands

## 13.1 Control-plane quick setup

Run this on the control-plane node.

Check and adjust the variables first:

```bash
export NFS_SERVER_IP="192.168.88.100"
```

Then run:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl ca-certificates gnupg lsb-release nfs-common

sudo swapoff -a

sudo mkdir -p /etc/systemd/zram-generator.conf.d
sudo tee /etc/systemd/zram-generator.conf.d/disable-zram.conf >/dev/null <<'EOF'
[zram0]
zram-size = 0
EOF

sudo systemctl daemon-reload

sudo mkdir -p /mnt/nfs-storage 
sudo chown root:root /mnt/nfs-storage 
sudo chmod 755 /mnt/nfs-storage 

sudo tee -a /etc/fstab >/dev/null <<EOF
${NFS_SERVER_IP}:/export/k8s-storage /mnt/nfs-storage nfs defaults,_netdev,vers=3,nolock,hard,intr,noatime,nodiratime,rsize=131072,wsize=131072,timeo=150,retrans=5 0 0
EOF

sudo systemctl daemon-reload
sudo mount -a

curl -sfL https://get.k3s.io | sh -
```

If cgroups or zram were changed, reboot:

```bash
sudo reboot
```

After reboot:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
kubectl get nodes -o wide
```

## 13.2 Worker quick setup

Run this on each worker node.

Check and adjust the variables first:

```bash
export K3S_SERVER_IP="192.168.88.213"
export K3S_NODE_TOKEN="<replace-with-token-from-control-plane>"
export NFS_SERVER_IP="192.168.88.100"
```

Then run:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl ca-certificates gnupg lsb-release nfs-common

sudo swapoff -a

sudo mkdir -p /etc/systemd/zram-generator.conf.d
sudo tee /etc/systemd/zram-generator.conf.d/disable-zram.conf >/dev/null <<'EOF'
[zram0]
zram-size = 0
EOF

sudo systemctl daemon-reload

sudo mkdir -p /mnt/nfs-storage
sudo chown root:root /mnt/nfs-storage 
sudo chmod 755 /mnt/nfs-storage

sudo tee -a /etc/fstab >/dev/null <<EOF
${NFS_SERVER_IP}:/export/k8s-storage /mnt/nfs-storage nfs defaults,_netdev,vers=3,nolock,hard,intr,noatime,nodiratime,rsize=131072,wsize=131072,timeo=150,retrans=5 0 0
EOF

sudo systemctl daemon-reload
sudo mount -a

curl -sfL https://get.k3s.io | \
  K3S_URL=https://${K3S_SERVER_IP}:6443 \
  K3S_TOKEN=${K3S_NODE_TOKEN} \
  sh -
```

Check the worker:

```bash
sudo systemctl status k3s-agent
```

From the control-plane node:

```bash
kubectl get nodes -o wide
```

Optional on worker nodes only:

```bash
sudo raspi-config
```

Then enable:

```text
Performance Options -> Overlay File System
```

---

# 14. Troubleshooting

## Check node health

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

## Check K3s server

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -n 100 --no-pager
```

## Check K3s worker

```bash
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -n 100 --no-pager
```

## Check swap

```bash
free -h
swapon --show
```

## Check cgroups

```bash
cat /proc/cmdline
```

## Check NFS mounts

```bash
findmnt | grep nfs
df -h | grep nfs
showmount -e 192.168.88.100
```

## Test NFS mount manually

```bash
sudo mount -t nfs 192.168.88.100:/export/k8s-storage /mnt/nfs-storage
```

## Check recent mount errors

```bash
dmesg | tail -n 50
```

## Check overlay filesystem status

```bash
findmnt /
mount | grep overlay || true
```

---

# 15. References

- K3s install script: https://get.k3s.io
- K3s install notes: https://github.com/filip-lebiecki/k3s-install
- Raspberry Pi K3s guide: https://medium.com/@stevenhoang/step-by-step-guide-installing-k3s-on-a-raspberry-pi-4-cluster-8c12243800b9
