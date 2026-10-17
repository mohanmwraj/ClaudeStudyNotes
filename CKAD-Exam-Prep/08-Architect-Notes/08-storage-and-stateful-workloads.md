# 08 · Storage and stateful workloads

> **Exam link:** [01 · Application Design and Build](../01-Application-Design-and-Build/README.md) (persistent and ephemeral volumes, choosing workload resources such as StatefulSets). The exam asks you to bind a PVC; production asks who restores the data when the zone is gone.

Stateless services are easy to make reliable; data is where outages become incidents with permanent consequences. Treat every piece of state as a product: an owner, an SLO, backups, and restores that have actually been tested.

## Principles

1. **Stateless by default.** Push state to managed services and object storage first.
2. **Managed service > operator > hand-rolled StatefulSet** for databases and brokers.
3. **Data outlives clusters.** Production volumes use `reclaimPolicy: Retain`; backups live outside the cluster and the region.
4. **Storage has topology.** Zonal disks pin pods to a zone; bind volumes where the pod is scheduled (`WaitForFirstConsumer`) and replicate at the data layer for zone failure.
5. **Growth is routine:** `allowVolumeExpansion: true` and usage alerts long before the disk is full.
6. **RWX is a design smell for scale-out apps;** shared files belong in object storage.
7. **A backup is a restore you have tested,** with measured RPO and RTO.

## Recommended defaults

| Area | Default | Why |
|---|---|---|
| Default StorageClass | zonal block storage, `WaitForFirstConsumer`, `allowVolumeExpansion: true`, encrypted | correct zone, growable, secure |
| Production data class | same, plus `reclaimPolicy: Retain` | deleting a PVC must not delete the data |
| Databases | managed service; otherwise a mature operator (e.g. CloudNativePG for PostgreSQL) | HA, failover, backups, upgrades handled |
| StatefulSet PVC retention | `whenDeleted: Retain`, `whenScaled: Retain` (the defaults; GA v1.32) | explicit; `Delete` only for disposable environments |
| Single-writer guarantee | `ReadWriteOncePod` (GA v1.29) | `ReadWriteOnce` still allows several pods on the same node |
| Scratch space | `emptyDir` with `sizeLimit`, or generic ephemeral volumes | no node disk exhaustion, cleaned up with the pod |
| Backups | Velero (objects + volumes) and database-native backups (WAL/PITR) to object storage in another region | crash-consistent snapshots are not enough for databases |
| Restore tests | automated, at least quarterly, into a scratch namespace or cluster | proves RPO/RTO |
| Monitoring | `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes` alerts at 80% and 90% | disk full = outage |

## Decision tables / trade-offs

### StorageClass design

| Field | Choices | Production guidance |
|---|---|---|
| `provisioner` | the CSI driver (e.g. `ebs.csi.aws.com`, `pd.csi.storage.gke.io`, `disk.csi.azure.com`) | in-tree volume plugins are migrated to CSI |
| `parameters` | driver-specific (disk type, IOPS, throughput, encryption key) | publish a small catalogue instead of per-team classes |
| `reclaimPolicy` | `Delete` (default for dynamic provisioning) / `Retain` | `Retain` for anything you cannot recreate; audit orphaned PVs (they still cost money) |
| `volumeBindingMode` | `Immediate` (default) / `WaitForFirstConsumer` | `WaitForFirstConsumer` for zonal disks |
| `allowVolumeExpansion` | `true` / `false` | `true`; recovery from failed expansion is GA since v1.34 |
| `allowedTopologies` | restrict zones | only for special cases; it fights topology spread |
| default class | annotation `storageclass.kubernetes.io/is-default-class: "true"` | exactly one default; `storageClassName: ""` disables dynamic provisioning |

Changing StorageClass parameters never changes existing volumes. To change IOPS/throughput of a live volume use a `VolumeAttributesClass` (`storage.k8s.io/v1`, GA v1.34) if your CSI driver supports volume modification (verify current status per driver).

### Binding mode

| Mode | What happens | Use |
|---|---|---|
| `Immediate` | the volume is provisioned when the PVC is created, in some zone; the pod may then land in another zone and stay Pending ("volume node affinity conflict") | single-zone clusters; storage reachable from every zone (network file systems) |
| `WaitForFirstConsumer` | provisioning waits until a pod using the PVC is scheduled, then happens in that pod's zone, honouring its constraints | zonal block storage (the normal case) |

### Where should the database run?

| Option | You operate | Pros | Cons | Choose when |
|---|---|---|---|---|
| Managed service (RDS, Cloud SQL, Azure Database, ...) | schema and queries | HA, backups, PITR, patching, support | cost; network path out of the cluster; provider limits | default for production OLTP |
| Operator (CloudNativePG, Strimzi for Kafka, Percona/Crunchy for PostgreSQL, Vitess for MySQL, ...) | operator + capacity + on-call for data | declarative HA, failover, backups to object storage, rolling upgrades, portability | you own data incidents; operator maturity and upgrades vary | in-cluster data needed (latency, portability, cost at scale) and DB skills exist |
| Hand-rolled StatefulSet | everything | full control | failover, split-brain, backups and upgrades are yours | caches, dev/test, simple single-instance tools |

CloudNativePG runs PostgreSQL with a primary/standby architecture on native streaming replication, automated failover and continuous backup to object storage - since CNPG 1.26 through the Barman Cloud Plugin (CNCF status: verify current status). Its `ScheduledBackup` uses a six-field cron expression with **seconds first**, unlike a CronJob. Whatever operator you pick, plan how you upgrade **the operator itself**.

### StatefulSet essentials

| Feature | Field | Notes |
|---|---|---|
| Stable identity | pod names `<name>-0..N-1`, headless `serviceName` | DNS `<pod>.<svc>.<ns>.svc.cluster.local` |
| Per-pod storage | `volumeClaimTemplates` | PVC names `<template>-<pod>`; survive pod rescheduling |
| Ordering | `podManagementPolicy: OrderedReady` (default) / `Parallel` | `Parallel` for faster scale when peers do not need ordering |
| Staged upgrades | `updateStrategy.rollingUpdate.partition` | upgrade only ordinals >= partition: a stateful canary |
| Faster rollouts | `updateStrategy.rollingUpdate.maxUnavailable` | beta in v1.35, but its default enablement changed between v1.35 patch releases (on by default again in v1.37) - do not rely on it without checking your exact version |
| Availability | `minReadySeconds` (GA v1.25) | like Deployments |
| PVC lifecycle | `persistentVolumeClaimRetentionPolicy` (GA v1.32): `whenDeleted`, `whenScaled` = `Retain` (default) or `Delete` | `whenScaled: Delete` removes the PVCs of scaled-down ordinals |

### Backups and disaster recovery

| What | How | Note |
|---|---|---|
| Kubernetes objects | Git (GitOps) is the primary source; Velero for cluster state and non-Git objects | restore = re-sync + restore data |
| Volumes | CSI `VolumeSnapshot` (GA since v1.20) via Velero, plus the CSI snapshot data mover or file-system backup (Kopia) to copy data to object storage | a snapshot in the same account/region is not a backup |
| Databases | engine-native continuous backup (WAL archiving / PITR) via the operator or managed service | app-consistent, point-in-time |
| Multi-volume consistency | CSI volume group snapshots (verify current status), or DB-native backups | crash-consistent across volumes |
| External state | secret manager, DNS, certificates, cloud resources via IaC | often forgotten in DR plans |

| DR pattern | RTO | Cost | Notes |
|---|---|---|---|
| Backup and restore | hours | low | test it; restore speed is the bottleneck |
| Pilot light | tens of minutes | medium | data replicated, compute scaled to zero in the DR region |
| Warm standby | minutes | higher | scaled-down full stack, promote on failover |
| Active/active | ~0 | highest | stateful data across regions is the hard part (conflicts, latency) |

### Shared file storage (RWX)

| Option | Fit | Watch out |
|---|---|---|
| Object storage via SDK (S3, GCS, Blob) | best for scale-out apps, uploads, artifacts | not a POSIX filesystem |
| Managed NFS via CSI (EFS, Azure Files, Filestore) | lift-and-shift apps that need a shared directory | latency, throughput limits, locking semantics, per-GB cost |
| CephFS via Rook (CNCF graduated) | self-managed RWX/RWO/object | operational expertise required |
| Longhorn RWX (CNCF incubating) | small clusters, edge | performance limits |

Access modes: `ReadWriteOnce` (one **node**), `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod` (one **pod**). Never run a database on NFS-style RWX storage.

### Data locality

- A zonal disk ties its pod to that zone: on zone failure the pod cannot move. HA therefore comes from **replicas in different zones, each with its own volume** (3 instances, zone spread with `DoNotSchedule`, `minDomains: 3`).
- Local NVMe (`local` PVs or a local-storage CSI driver) gives the best latency but loses data with the node; use it only under replicated databases. Storage capacity tracking (`CSIStorageCapacity`, GA v1.24) lets the scheduler pick nodes with free local capacity.
- Cross-zone replication traffic is billed by most clouds: include it in the cost model.
- Scratch: `emptyDir` with `sizeLimit`; `medium: Memory` counts against the container memory limit; generic ephemeral volumes (`ephemeral.volumeClaimTemplate`) give per-pod PVCs that die with the pod.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Production data on a `reclaimPolicy: Delete` class | `kubectl delete pvc` (or namespace) destroys data | `Retain` class for production |
| `Immediate` binding with zonal disks | pods Pending with volume node affinity conflicts | `WaitForFirstConsumer` |
| Snapshots in the same account/region called "backups" | region or account loss = data loss | copy off-site; DB-native PITR |
| Never-tested restores | unknown RTO, broken backups found during the incident | scheduled restore drills |
| Single-replica database StatefulSet without backups | one disk failure away from data loss | operator with replicas + backups, or managed DB |
| Database on RWX/NFS | corruption, poor performance | block storage, replicated at DB level |
| `hostPath` for application data | node-bound, insecure, not portable | PVCs; blocked by PSA `baseline`/`restricted` anyway |
| No volume usage alerts | disk full -> write failures -> outage | alert on `kubelet_volume_stats_*` |
| Assuming PVCs are deleted on scale-down (or the reverse) | orphaned volumes, or surprise data loss with `whenScaled: Delete` | set `persistentVolumeClaimRetentionPolicy` explicitly |
| Editing StorageClass parameters to "upgrade" disks | nothing changes for existing PVs | `VolumeAttributesClass` or migration |

## Reference YAML

Production StorageClass (AWS EBS CSI shown; parameters are driver-specific):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: prod-retain
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "6000"
  throughput: "250"
  encrypted: "true"                # kmsKeyId: <key ARN> for a customer-managed key
reclaimPolicy: Retain              # PV and data survive PVC deletion
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

StatefulSet with explicit PVC retention and a partitioned rollout (a minimal sketch; use an operator for real databases):

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg
  namespace: data
spec:
  serviceName: pg                  # headless Service (see 05)
  replicas: 3
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2                 # only pg-2 gets the new template until you lower this
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
  selector:
    matchLabels:
      app.kubernetes.io/name: pg
  template:
    metadata:
      labels:
        app.kubernetes.io/name: pg
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999             # "postgres" user in the official image
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - name: postgres
          containerPort: 5432
        env:
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        - name: POSTGRES_PASSWORD_FILE
          value: /var/run/secrets/pg/password
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            memory: 1Gi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: pg-secret
          mountPath: /var/run/secrets/pg
          readOnly: true
      volumes:
      - name: pg-secret
        secret:
          secretName: pg-credentials
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: prod-retain
      accessModes: ["ReadWriteOncePod"]   # CSI driver must support it; otherwise ReadWriteOnce
      resources:
        requests:
          storage: 100Gi
```

CloudNativePG cluster with continuous backup through the Barman Cloud Plugin (requires the CNPG operator and the plugin; the operator's native `barmanObjectStore` integration is deprecated since CNPG 1.26; replace `<backup-bucket>`):

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: shop-db-backups
  namespace: data
spec:
  configuration:
    destinationPath: s3://<backup-bucket>/shop-db/   # bucket in another region/account
    s3Credentials:
      accessKeyId:
        name: shop-db-backup-creds
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: shop-db-backup-creds
        key: ACCESS_SECRET_KEY
    wal:
      compression: gzip
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: shop-db
  namespace: data
spec:
  instances: 3                     # 1 primary + 2 streaming replicas, automated failover
  storage:
    size: 100Gi
    storageClass: prod-retain
  plugins:
  - name: barman-cloud.cloudnative-pg.io
    isWALArchiver: true            # continuous WAL archiving -> point-in-time recovery
    parameters:
      barmanObjectName: shop-db-backups
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: shop-db-daily
  namespace: data
spec:
  schedule: "0 0 2 * * *"          # six fields, SECONDS first (Go cron): daily at 02:00:00
  backupOwnerReference: self
  cluster:
    name: shop-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

Snapshot and restore with CSI (requires the snapshot CRDs/controller and a driver that supports snapshots):

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshots
driver: ebs.csi.aws.com
deletionPolicy: Retain             # keep the snapshot if the VolumeSnapshot object is deleted
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: data-pg-0-2026-10-17
  namespace: data
spec:
  volumeSnapshotClassName: ebs-snapshots
  source:
    persistentVolumeClaimName: data-pg-0
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pg-restore
  namespace: data
spec:
  storageClassName: prod-retain
  dataSource:                      # new volume pre-populated from the snapshot
    name: data-pg-0-2026-10-17
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 100Gi
```

Nightly Velero backup of two namespaces (requires Velero with a backup storage location):

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: shop-nightly
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
    - shop
    - data
    snapshotVolumes: true
    ttl: 720h0m0s                  # keep 30 days
```

## Checklist

- [ ] Each stateful component has an owner, RPO/RTO targets and a documented restore procedure.
- [ ] Databases run as managed services or via a mature operator; hand-rolled StatefulSets only for non-critical state.
- [ ] Production StorageClass: `Retain`, `WaitForFirstConsumer`, expansion enabled, encrypted.
- [ ] StatefulSets set `persistentVolumeClaimRetentionPolicy` explicitly; single writers use `ReadWriteOncePod`.
- [ ] Replicas spread across zones, each with its own volume.
- [ ] Backups (Velero + DB-native PITR) copied to another region/account; restores tested on a schedule.
- [ ] Volume usage alerts at 80/90%; orphaned PVs reviewed monthly.
- [ ] No `hostPath` and no NFS-backed databases; scratch space uses `emptyDir` with `sizeLimit`.

## References

- Volumes: https://kubernetes.io/docs/concepts/storage/volumes/
- Persistent volumes (access modes, reclaim policy): https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- Storage classes: https://kubernetes.io/docs/concepts/storage/storage-classes/
- Volume attributes classes: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/
- Volume snapshots: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- Storage capacity: https://kubernetes.io/docs/concepts/storage/storage-capacity/
- Ephemeral volumes: https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/
- StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- StatefulSet basics: https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/
- Operator pattern: https://kubernetes.io/docs/concepts/extend-kubernetes/operator/
- Velero: https://velero.io/docs/main/
- Velero Schedule API: https://velero.io/docs/main/api-types/schedule/
- CloudNativePG docs: https://cloudnative-pg.io/docs/current/
- CloudNativePG backup and recovery: https://cloudnative-pg.io/docs/devel/backup/
- Barman Cloud Plugin for CloudNativePG: https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/
- Rook: https://rook.io/
- Longhorn: https://longhorn.io/
- AWS EBS CSI StorageClass parameters (example driver): https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md
