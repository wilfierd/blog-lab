# Tài liệu Hệ thống K8s On-Premises — Blog App

---

## 1. Tổng quan kiến trúc

```
Internet
    │
    │  (local network 192.168.122.0/24)
    ▼
┌─────────────────────────────────────────────────────┐
│  Host Machine (Fedora, KVM/libvirt)                 │
│  Disk: /mnt/G (427GB NVMe)                         │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │ k8s-master-1 │  │ k8s-master-2 │  │k8s-master │ │
│  │ .111         │  │ .112         │  │-3  .113   │ │
│  │ control-plane│  │ worker       │  │ worker    │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
│                                                     │
│  ┌──────────────┐                                   │
│  │ rancher-host │                                   │
│  │ .114         │                                   │
│  │ Rancher UI   │                                   │
│  └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
```

---

## 2. Phần cứng & VM

| Node | IP | CPU | RAM | OS Disk | Data Disk | Role |
|---|---|---|---|---|---|---|
| k8s-master-1 | 192.168.122.111 | 2 core | 2.5GB | 18GB (vda) | — | Control Plane |
| k8s-master-2 | 192.168.122.112 | 2 core | 4.3GB | 18GB (vda) | 20GB (vdb→/data) | Worker |
| k8s-master-3 | 192.168.122.113 | 2 core | 3.5GB | 18GB (vda) | 20GB (vdb→/data) | Worker |
| rancher-host | 192.168.122.114 | 2 core | — | — | — | Rancher Server |

**Tại sao tách data disk:**
- OS disk chứa container images, logs, kubelet ephemeral storage → dễ đầy → trigger `disk-pressure` taint → pods bị evict
- Data disk `/data` chỉ chứa PVC data (postgres, minio, prometheus) → tách biệt, không ảnh hưởng scheduling

**Tại sao master-1 không chạy workload:**
- etcd + kube-apiserver chiếm ~400MB RAM liên tục
- Taint `node-role.kubernetes.io/control-plane:NoSchedule` ngăn pod schedule lên
- Đảm bảo control plane luôn có đủ tài nguyên, không bị app tranh giành

---

## 3. Network

### 3.1 Dải IP

| Layer | Dải | Ví dụ |
|---|---|---|
| Node (VM) | 192.168.122.0/24 | master-1: .111, master-2: .112 |
| Pod (Calico) | 172.17.0.0/16 | blog-app pod: 172.17.182.85 |
| Service (ClusterIP) | 10.96.0.0/12 | blog-app svc: 10.101.183.242 |

### 3.2 Flow request từ ngoài vào

```
Client (browser)
    │
    │ HTTP blog.local
    ▼
NGINX Ingress Controller (DaemonSet, port 80/443 trên mọi worker)
    │
    │ Route theo Host header
    ▼
Service/ClusterIP blog-app :8080
    │
    │ kube-proxy load balance
    ▼
Pod blog-app (replica 1 trên master-2 HOẶC replica 2 trên master-3)
    │
    ├─→ postgres.data.svc.cluster.local:5432 (ClusterIP → pod master-2)
    └─→ minio.data.svc.cluster.local:9000   (ClusterIP → pod master-2)
```

### 3.3 Tại sao dùng Ingress thay NodePort/LoadBalancer

| Loại | Cách hoạt động | Ưu điểm | Nhược điểm |
|---|---|---|---|
| **NodePort** | Mở port ngẫu nhiên (30000-32767) trên mọi node | Đơn giản | Port xấu, phải nhớ port, không route theo domain |
| **LoadBalancer** | Yêu cầu cloud provider tạo LB bên ngoài | Tự động, production grade | Không có trên on-prem (cần MetalLB) |
| **Ingress** (đang dùng) | HTTP reverse proxy trong cluster, route theo Host/Path | 1 IP cho nhiều domain, TLS termination, annotations | Cần Ingress Controller |

**NGINX Ingress Controller** chạy như DaemonSet trên các worker — mọi worker đều nhận traffic và forward vào đúng Service.

---

## 4. Namespace & Resource Policy

### 4.1 Namespace layout

```
kube-system          → K8s internal (etcd, apiserver, calico, coredns...)
ingress-nginx        → NGINX Ingress Controller
local-path-storage   → Local Path Provisioner (cấp PVC)
cattle-system        → Rancher agent (cluster management)
monitoring           → Prometheus + Grafana + Alertmanager
blog                 → Blog App (stateless pods only)
data                 → PostgreSQL + MinIO (stateful data layer)
windgo               → App khác
```

**Tại sao tách `data` namespace riêng:**
- Blog-app có HPA 2→4 replicas → nếu chung namespace, scale mạnh có thể cướp resource của postgres/minio
- ResourceQuota riêng cho data layer → postgres/minio luôn có đủ CPU/RAM, không bị app tranh giành
- NetworkPolicy rõ ràng: `blog` → `data` allow, mọi namespace khác deny
- Xóa/redeploy blog-app không ảnh hưởng data

### 4.2 ResourceQuota

| Namespace | CPU Request | CPU Limit | RAM Request | RAM Limit | Pods |
|---|---|---|---|---|---|
| blog | 2 core | 4 core | 2Gi | 4Gi | 20 |
| data | 1 core | 2 core | 1Gi | 2Gi | 10 |
| monitoring | 4 core | 8 core | 6Gi | 12Gi | 40 |
| windgo | 2 core | 4 core | 2Gi | 4Gi | 20 |

### 4.3 LimitRange (default cho container không khai báo)

| Namespace | Default CPU Request | Default CPU Limit | Default RAM Request | Default RAM Limit |
|---|---|---|---|---|
| blog | 50m | 200m | 64Mi | 256Mi |
| data | 100m | 500m | 256Mi | 512Mi |
| monitoring | 100m | 500m | 128Mi | 512Mi |

### 4.4 NetworkPolicy

```
blog namespace:
  ✅ ingress-nginx → blog-app:8080    (web traffic)
  ✅ monitoring → blog-app:8080       (metrics scrape)
  ❌ mọi traffic khác bị block

data namespace:
  ✅ blog → postgres:5432             (database)
  ✅ blog → minio:9000                (object storage API)
  ✅ ingress-nginx → minio:9001       (MinIO console UI)
  ❌ mọi traffic khác bị block

monitoring namespace:
  ✅ ingress-nginx → grafana          (dashboard UI)
  ✅ prometheus egress ra ngoài       (scrape metrics mọi namespace)
  ❌ mọi ingress khác bị block
```

---

## 5. Workload Distribution

```
k8s-master-1 (2.5GB RAM) — Control Plane Only:
├── etcd                    (~100MB RAM)
├── kube-apiserver          (~244MB RAM)
├── kube-controller-manager (~50MB RAM)
├── kube-scheduler          (~30MB RAM)
└── node-exporter           (50m CPU / 32Mi RAM)

k8s-master-2 (4.3GB RAM) — Worker:
├── [ns: blog]
│   └── blog-app replica-1      (100m CPU / 128Mi RAM)
├── [ns: data]
│   ├── postgres-0              (100m CPU / 256Mi RAM)  ← PVC 5Gi @ /data
│   └── minio-0                 (100m CPU / 256Mi RAM)  ← PVC 5Gi @ /data
├── [ns: monitoring]
│   └── kube-prom-grafana       (100m CPU / 128Mi RAM)
└── node-exporter               (50m CPU / 32Mi RAM)

k8s-master-3 (3.5GB RAM) — Worker:
├── [ns: blog]
│   └── blog-app replica-2      (100m CPU / 128Mi RAM)
├── [ns: monitoring]
│   ├── prometheus-0            (200m CPU / 512Mi RAM)  ← PVC 5Gi @ /data
│   ├── alertmanager-0          (50m CPU / 64Mi RAM)    ← PVC 1Gi @ /data
│   ├── kube-state-metrics      (50m CPU / 64Mi RAM)
│   └── prometheus-operator     (50m CPU / 64Mi RAM)
└── node-exporter               (50m CPU / 32Mi RAM)
```

---

## 6. Storage

### 6.1 Local Path Provisioner

PVC được tạo dưới dạng thư mục trực tiếp trên disk của node:

```
/data/                              ← mount point của vdb1 (data disk)
└── local-path-provisioner/
    ├── pvc-xxx-postgres/           ← data PostgreSQL
    ├── pvc-xxx-minio/              ← data MinIO
    └── pvc-xxx-prometheus/         ← data Prometheus
```

**Cấu hình nodePathMap:**
```json
{
  "nodePathMap": [
    { "node": "k8s-master-2", "paths": ["/data"] },
    { "node": "k8s-master-3", "paths": ["/data"] },
    { "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES", "paths": ["/opt/local-path-provisioner"] }
  ]
}
```

**Hạn chế của local-path:**
- PVC bị pin vào 1 node cụ thể (nodeAffinity) — pod không thể di chuyển sang node khác
- Không có replication — node chết = mất data
- Không hỗ trợ `ReadWriteMany`

### 6.2 PVC Summary

| PVC | Namespace | Size | Node | Path |
|---|---|---|---|---|
| postgres-data-postgres-0 | data | 5Gi | master-2 | /data |
| minio-data-minio-0 | data | 5Gi | master-2 | /data |
| prometheus-db | monitoring | 5Gi | master-2 | /data |
| alertmanager-db | monitoring | 1Gi | master-3 | /data |

---

## 7. Helm Charts

### 7.1 blog-app (custom chart)

```
helm/blog-app/
├── Chart.yaml
├── values.yaml          ← image, replicas, resources, config
├── secrets-values.yaml  ← gitignored, credentials thật
└── templates/
    ├── deployment.yaml  ← 2 replicas, envFrom configmap+secret
    ├── service.yaml     ← ClusterIP :8080
    ├── ingress.yaml     ← blog.local → nginx
    ├── hpa.yaml         ← autoscale 2→4 replicas khi CPU >70%
    ├── configmap.yaml   ← DB_HOST, AWS_ENDPOINT_URL, ...
    └── secret.yaml      ← DB_PASSWORD, SESSION_SECRET, ...
```

**values.yaml key config:**
```yaml
image:
  repository: wilfierd34/blog-app
  tag: latest

replicaCount: 2

hpa:
  minReplicas: 2
  maxReplicas: 4
  cpuUtilization: 70

config:
  dbHost: postgres.data.svc.cluster.local
  awsEndpointURL: http://minio.data.svc.cluster.local:9000
  awsBucketName: blog-uploads
```

### 7.2 kube-prometheus-stack

```yaml
prometheus:
  prometheusSpec:
    nodeSelector: { node-role.kubernetes.io/worker: "" }
    retention: 15d
    storage: 5Gi

grafana:
  nodeSelector: { node-role.kubernetes.io/worker: "" }
  ingress:
    host: grafana.local

alertmanager:
  config:
    smtp → vexbravor@gmail.com
```

---

## 8. CI/CD Pipeline

```
Developer push → main branch
        │
        ▼
GitHub Actions (self-hosted runner — máy local Fedora)
        │
        ├─ Job 1: build-and-push
        │   ├── podman build --platform linux/amd64
        │   ├── tag: <SHA8> + latest
        │   └── podman push → Docker Hub
        │
        └─ Job 2: deploy (needs Job 1)
            ├── rsync helm/blog-app/ → master-1:/tmp/helm/
            ├── rsync secrets-values.yaml → master-1
            └── SSH → master-1:
                ├── helm upgrade --install blog-app
                │   --set image.tag=<SHA8>
                │   --atomic --timeout 5m
                └── kubectl rollout status deployment/blog-app
```

**GitHub Secrets cần thiết:**
```
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

**Secrets file trên runner** (không commit lên git):
```
$HOME/secrets/blog-secrets-values.yaml
```

---

## 9. Rollback & Backup

### 9.1 Rollback App

```bash
# Xem lịch sử deploy
helm history blog-app -n blog

# Rollback về revision trước
helm rollback blog-app -n blog

# Rollback về revision cụ thể
helm rollback blog-app 3 -n blog
```

### 9.2 Backup PostgreSQL (CronJob — cần bổ sung)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: data
spec:
  schedule: "0 2 * * *"   # 2AM mỗi ngày
  jobTemplate:
    spec:
      template:
        spec:
          nodeSelector:
            node-role.kubernetes.io/worker: ""
          containers:
          - name: backup
            image: postgres:15-alpine
            command:
            - sh
            - -c
            - |
              pg_dump -h postgres -U admins blogdb \
                > /backup/blogdb-$(date +%Y%m%d).sql
            envFrom:
            - secretRef:
                name: postgres-secret
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            hostPath:
              path: /data/backups
          restartPolicy: OnFailure
```

### 9.3 Kế hoạch sự cố

| Sự cố | Phát hiện | Hành động |
|---|---|---|
| Pod crash | Alertmanager → email | `kubectl logs`, `kubectl describe pod` |
| Worker node down | PodNotReady alert 5m | K8s tự reschedule pod stateless; StatefulSet (postgres/minio) bị stuck vì PVC pin |
| Master-1 down | API server mất | Cluster vẫn chạy nhưng không deploy được — khởi động lại VM |
| Disk đầy | PVCAlmostFull alert 85% | Xóa data cũ hoặc expand disk: `virsh blockresize` + `growpart` + `lvextend` |
| etcd corrupt | API server không lên | Restore: `etcdctl snapshot restore` |
| Helm deploy fail | `--atomic` tự rollback | `helm history`, fix rồi redeploy |

---

## 10. Alert Rules

| Alert | Điều kiện | Severity | Action |
|---|---|---|---|
| BruteForceLoginDetected | >20 login fail trong 5m | critical | Check IP, block |
| DBConnectionPoolHigh | pool >85% | warning | Check slow queries |
| PodCrashLooping | restart rate > 0 trong 2m | warning | `kubectl logs` |
| PodNotReady | pod blog not ready 5m | critical | `kubectl describe` |
| PVCAlmostFull | disk >85% | warning | Dọn data cũ |
| PostgresPVCCritical | postgres disk >90% | critical | Mở rộng ngay |

---

## 11. Flow Diagram

### Service Flow

```
[Client] ──HTTP blog.local──▶ [NGINX Ingress @ worker]
                                        │
                              route Host: blog.local
                                        │
                                        ▼
                          [Service: blog-app ClusterIP :8080]
                                        │
                          ┌─────────────┴─────────────┐
                          ▼                           ▼
               [Pod blog-app @ master-2]   [Pod blog-app @ master-3]
               172.17.182.85               172.17.168.15
                          │
                ┌─────────┴──────────┐
                ▼                    ▼
    [postgres-0 @ master-2]    [minio-0 @ master-2]
    ns:data  :5432             ns:data  :9000
```

### Monitoring Flow

```
[node-exporter] × 3 nodes ─────────────────────┐
[kube-state-metrics @ master-3] ───────────────┤
[blog-app :8080/metrics] ──────────────────────┤
                                                ▼
                                   [Prometheus @ master-3]
                                   scrape mỗi 30s, lưu 15d
                                                │
                                   ┌────────────┴────────────┐
                                   ▼                         ▼
                             [Grafana]               [Alertmanager]
                             grafana.local            → Gmail alert
                             dashboard K8s + app
```

### System IP & Resource

```
192.168.122.111 (master-1) — 2CPU/2.5GB
├── etcd :2379/:2380
├── kube-apiserver :6443
└── [NO workload — taint NoSchedule]

192.168.122.112 (master-2) — 2CPU/4.3GB
├── OS disk 18GB (vda) — images, logs
├── Data disk 20GB (vdb→/data) — PVC data
├── blog-app :8080
├── postgres :5432  ← PVC 5Gi /data
├── minio :9000/:9001 ← PVC 5Gi /data
└── grafana :3000

192.168.122.113 (master-3) — 2CPU/3.5GB
├── OS disk 18GB (vda) — images, logs
├── Data disk 20GB (vdb→/data) — PVC data
├── blog-app :8080
├── prometheus :9090 ← PVC 5Gi /data
└── alertmanager :9093 ← PVC 1Gi /data

192.168.122.114 (rancher) — Rancher Server
└── Rancher UI :443
```

---

## 12. Checklist vận hành

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# etcd health
kubectl -n kube-system exec etcd-k8s-master-1 -- \
  etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Disk workers
ssh nguyenhieu@192.168.122.112 "df -h / /data"
ssh nguyenhieu@192.168.122.113 "df -h / /data"

# ResourceQuota usage
kubectl describe resourcequota -n blog
kubectl describe resourcequota -n data
kubectl describe resourcequota -n monitoring

# Blog app health
curl http://blog.local/api/health

# Helm releases
helm list -A
```

---

## 13. Kịch bản test

### Test HA blog-app

```bash
# Kill pod trên master-2 → phải tạo lại
kubectl delete pod -n blog -l app=blog-app \
  --field-selector=spec.nodeName=k8s-master-2

# Verify K8s tạo lại pod
kubectl get pods -n blog -o wide -w

# Verify endpoint vẫn serve trong lúc restart
while true; do curl -s http://blog.local/api/health; sleep 1; done
```

### Test HPA autoscale

```bash
# Tạo load
kubectl run load-gen --image=busybox -n blog --restart=Never -- \
  sh -c "while true; do wget -q -O- http://blog-app:8080; done"

# Watch HPA
kubectl get hpa -n blog -w

# Dọn
kubectl delete pod load-gen -n blog
```

### Test NetworkPolicy

```bash
# Pod ở namespace khác KHÔNG được vào postgres
kubectl run test --image=busybox -n windgo --restart=Never -- sleep 3600
kubectl exec -n windgo test -- nc -zv postgres.data.svc.cluster.local 5432
# Expected: timeout / refused

# Pod blog-app ĐƯỢC vào postgres (cross-namespace qua ClusterIP)
kubectl exec -n blog deploy/blog-app -- nc -zv postgres.data.svc.cluster.local 5432
# Expected: open
```

### Test rollback

```bash
# Deploy broken image
helm upgrade blog-app /tmp/helm/blog-app \
  --set image.tag=broken \
  -n blog --atomic --timeout 3m
# --atomic tự rollback nếu pod không healthy

# Manual rollback
helm rollback blog-app -n blog
```
