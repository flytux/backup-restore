# Backup and restore workload and volumes with velero and longhorn

- Install RKE2 Cluster
- Install Minio / Longhorn / Velero for backup and restore volumes
- Install sample nginx app
- Backup and restore nginx app with velero and longhorn
- Install velero and longhorn at additional DR cluster
- Connect backup location s3 to DR cluster
- velero restore from backup will restore workload and pv at DR cluster

---
**1) Install RKE2**

```bash
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server --now

mkdir ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown k8sadm ~/.kube/config

curl -LO "https://dl.k8s.io/release/v1.25.9/bin/linux/amd64/kubectl"
chmod 755 kubectl && sudo mv kubectl /usr/local/bin
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF >> ~/.bashrc

# k8s alias

source <(kubectl completion bash)
complete -o default -F __start_kubectl k

alias k=kubectl
alias vi=vim
alias kn='kubectl config set-context --current --namespace'
alias kc='kubectl config use-context'
alias kcg='kubectl config get-contexts'
alias di='docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"'
alias kge="kubectl get events  --sort-by='.metadata.creationTimestamp'  -o 'go-template={{range .items}}{{.involvedObject.name}}{{\"\t\"}}{{.involvedObject.kind}}{{\"\t\"}}{{.message}}{{\"\t\"}}{{.reason}}{{\"\t\"}}{{.type}}{{\"\t\"}}{{.firstTimestamp}}{{\"\n\"}}{{end}}'"
EOF

source ~/.bashrc
```
---

**2) Install Minio**
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.22/deploy/local-path-storage.yaml

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
        persistentVolumeClaim:
          claimName: pvc-minio
      containers:
      - name: minio
        image: minio/minio:RELEASE.2021-02-14T04-01-33Z
        imagePullPolicy: IfNotPresent
        args:
        - server
        - /storage
        env:
        - name: MINIO_ACCESS_KEY
          value: "minio"
        - name: MINIO_SECRET_KEY
          value: "minio123"
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: storage
          mountPath: "/storage"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-minio
  namespace: minio
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
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
  selector:
    component: minio

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio
  namespace: minio
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
              number: 9000

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
        - "mc --config-dir=/config config host add velero http://minio.minio:9000 minio minio123 && mc --config-dir=/config mb -p velero/velero && mc --config-dir=/config mb -p velero/longhorn"
        volumeMounts:
        - name: config
          mountPath: "/config"
EOF
```
---

**3) Install Longhorn**

```bash

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
ingress:
  enabled: true
  ingressClassName: nginx
  host: longhorn.kw01
EOF

kubectl create ns longhorn-system

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
# AWS_ENDPOINTS: aHR0cDovL21pbmlvLmt3MDE= # http://minio.kw01

# Install longhorn chart
# RHEL
yum --setopt=tsflags=noscripts install iscsi-initiator-utils
echo "InitiatorName=$(/sbin/iscsi-iname)" > /etc/iscsi/initiatorname.iscsi
systemctl enable iscsid
systemctl start iscsid

apt -y install open-iscsi # Ubuntu

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

**4) Install CSI snapshot controller**
```bash

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

**5) Install Velero**

```bash
# Install Velero Cli
wget https://github.com/vmware-tanzu/velero/releases/download/v1.11.0/velero-v1.11.0-linux-amd64.tar.gz
tar xvf velero-v1.11.0-linux-amd64.tar.gz
mv velero-v1.11.0-linux-amd64/velero /usr/local/bin

# Install Velero Server
cat << EOF >> credential-velero
[default]
aws_access_key_id = minio
aws_secret_access_key = minio123
EOF

velero install --provider velero.io/aws \
 --bucket velero --image velero/velero:v1.11.0 \
 --plugins velero/velero-plugin-for-aws:v1.7.0,velero/velero-plugin-for-csi:v0.4.0 \
 --backup-location-config region=minio-default,s3ForcePathStyle="true",s3Url=http://minio.minio:9000 \
 --features=EnableCSI --snapshot-location-config region=minio-default \
 --use-volume-snapshots=true --secret-file=./credential-velero

```
---

**6) Install Nginx with PV**

```bash
kubectl apply -f - <<"EOF"
---
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-example
  labels:
    app: nginx

---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: nginx-logs
  namespace: nginx-example
  labels:
    app: nginx
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Mi

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: nginx-example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
      annotations:
        pre.hook.backup.velero.io/container: fsfreeze
        pre.hook.backup.velero.io/command: '["/sbin/fsfreeze", "--freeze", "/var/log/nginx"]'
        post.hook.backup.velero.io/container: fsfreeze
        post.hook.backup.velero.io/command: '["/sbin/fsfreeze", "--unfreeze", "/var/log/nginx"]'
    spec:
      volumes:
        - name: nginx-logs
          persistentVolumeClaim:
           claimName: nginx-logs
      containers:
      - image: nginx:1.17.6
        name: nginx
        ports:
        - containerPort: 80
        volumeMounts:
          - mountPath: "/var/log/nginx"
            name: nginx-logs
            readOnly: false
      - image: ubuntu:bionic
        name: fsfreeze
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: "/var/log/nginx"
            name: nginx-logs
            readOnly: false
        command:
          - "/bin/bash"
          - "-c"
          - "sleep infinity"
  
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  name: my-nginx
  namespace: nginx-example
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx
  type: ClusterIP
EOF

k run --rm -it curly --image=curlimages/curl sh
curl -v my-nginx.nginx-example

k exec -it $(k get pods -l app=nginx -o name) cat /var/log/nginx/access.log
```
---
**7) Create Backup and Restore**
```bash
# Create backup

velero backup create nginx --include-namespaces=nginx-example

k delete ns nginx-example

velero restore create --from-backup=nginx

# Check nginx log restored
k exec -it $(k get pods -l app=nginx -o name) cat /var/log/nginx/access.log

```
