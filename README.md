# Backup and restore k8s workloads with volume using velero and longhorn

---
**1) Install RKE2**

```bash
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server --now
```
---

**2) Install Minio**
```bash
kubectl apply -f - <<"EOF"
---
apiVersion: v1
kind: Namespace
metadata:
  name: minio

---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: minio
  name: minio
  labels:
    component: minio
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      component: minio
  template:
    metadata:
      labels:
        component: minio
    spec:
      volumes:
      - name: storage
        emptyDir: {}
      containers:
      - name: minio
        image: minio/minio:latest
        imagePullPolicy: IfNotPresent
        args:
        - server
        - --console-address ":9001"
        - /storage
        env:
        - name: MINIO_ACCESS_KEY
          value: "minio"
        - name: MINIO_SECRET_KEY
          value: "minio123"
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: storage
          mountPath: "/storage"
---
apiVersion: v1
kind: Service
metadata:
  namespace: minio
  name: minio
  labels:
    component: minio
spec:
  # ClusterIP is recommended for production environments.
  # Change to NodePort if needed per documentation,
  # but only if you run Minio in a test/trial environment, for example with Minikube.
  type: ClusterIP
  ports:
    - port: 9000
      targetPort: 9000
      protocol: TCP
      name: api
    - port: 9001
      targetPort: 9001
      protocol: TCP
      name: console
  selector:
    component: minio

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio
spec:
  ingressClassName: nginx
  rules:
  - host: "minio.kw01"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio
            port:
              number: 9001

---
apiVersion: batch/v1
kind: Job
metadata:
  namespace: minio
  name: minio-setup
  labels:
    component: minio
spec:
  template:
    metadata:
      name: minio-setup
    spec:
      restartPolicy: OnFailure
      volumes:
      - name: config
        emptyDir: {}
      containers:
      - name: mc
        image: minio/mc:latest
        imagePullPolicy: IfNotPresent
        command:
        - /bin/sh
        - -c
        - "mc --config-dir=/config config host add velero http://minio:9000 minio minio123 && mc --config-dir=/config mb -p velero/velero"
        volumeMounts:
        - name: config
          mountPath: "/config"
EOF
```
---

```bash

# Install longhorn

cat << EOF >> longhorn-values.yaml
persistence:
  # since we only have one node, we can have only 1 replica
  defaultClassReplicaCount: 1

defaultSettings:
  # This tells Longhorn to use the 'longhorn' bucket of our S3.
  backupTarget: s3://longhorn@dummyregion/
  # The secret where the MinIO credentials are stored.
  backupTargetCredentialSecret: minio-secret
  # Usually Longhorn does not store volumes on the node that it runs on. This setting allows that.
  replicaSoftAntiAffinity: true
  replicaZoneSoftAntiAffinity: true
EOF

kubectl apply -f - <<"EOF"
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: longhorn-system
type: Opaque

data:
  AWS_ACCESS_KEY_ID: bWluaW8= # minio
  AWS_SECRET_ACCESS_KEY: bWluaW8xMjM= # minio123
  AWS_ENDPOINTS: aHR0cDovL21pbmlvLm1pbmlvOjkwMDA= # http://minio.minio:9000
EOF

# Install Longhorn
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn \
    longhorn/longhorn \
    --namespace longhorn-system \
    --create-namespace \
    --values longhorn-values.yaml \
    --version 1.4.0 
```
---
```bash
# Install CSI snapshot controller

kubectl -n kube-system create -k "github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=release-5.0"
kubectl -n kube-system create -k "github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller?ref=release-5.0"

kubectl -n kube-system apply -f - <<"EOF"
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
metadata:
  name: longhorn-snapshot-vsc
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: driver.longhorn.io
deletionPolicy: Delete
parameters:
  type: bak
EOF
```
---

```bash
# Install Velero Cli
VELERO_VERSION=v1.10.0; \
    wget -c https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz -O - \
    | tar -xz -C /tmp/ \
    && sudo mv /tmp/velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin

# Install Velero Server

cat << EOF >> credentials-velero
[default]
aws_access_key_id = minio
aws_secret_access_key = minio123
EOF

$ velero install --provider velero.io/aws \
  --bucket velero --image velero/velero:v1.11.0 \
  --plugins velero/velero-plugin-for-aws:v1.7.0,velero/velero-plugin-for-csi:v0.4.0 \
  --backup-location-config region=kr-standard,s3ForcePathStyle="true",s3Url=http://minio.minio:9000 \
  --features=EnableCSI --use-volume-snapshots=true --secret-file=./credentials-velero

```
---

```bash

# Install Sample Application

---
kubectl -n logging apply -f - <<"EOF"
apiVersion: v1
kind: Namespace
metadata:
  name: nginx
---
kind: Pod
apiVersion: v1
metadata:
  namespace: nginx
  name: nginx
spec:
  nodeSelector:
    kubernetes.io/os: linux
  containers:
    - image: nginx
      name: nginx
      command: [ "sleep", "1000000" ]
      volumeMounts:
        - name: longhorndisk01
          mountPath: "/mnt/longhorndisk"
  volumes:
    - name: longhorndisk01
      persistentVolumeClaim:
        claimName: pvc-longhorndisk
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  namespace: nginx
  name: pvc-longhorndisk
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Mi
  storageClassName: longhorn
EOF

k run --rm -it curly --image=curlimages/curl sh
curl -v nginx.nginx

k exec -it $(k get pods -l app=nginx) cat /var/log/nginx/access.log

# Create backup

velero backup create nginx --include-namespaces=nginx

k delete ns nginx

velero restore create --from-backup=nginx 

