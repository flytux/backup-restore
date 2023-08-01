# Kube Fluentd Logging Operator

- elasticsearch and minio as sink
- control namespace logging with configmaps
- find tuing fluentd options with fluentd stanard functions

---

```bash
# Elastic Search 설치
$ kubectl create -f https://download.elastic.co/downloads/eck/2.8.0/crds.yaml
$ kubectl apply -f https://download.elastic.co/downloads/eck/2.8.0/operator.yaml

$ k create ns logging
$ cat <<EOF | kubectl apply -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
  namespace: logging
spec:
  version: 8.8.0
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
EOF

$ cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
  namespace: logging
spec:
  version: 8.8.0
  count: 1
  elasticsearchRef:
    name: quickstart
EOF
```

---

```bash
# Install Mioio
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

```bash
git clone https://github.com/vmware/kube-fluentd-operator.git
cd kube-fluentd-operator/charts/log-router
helm upgrade -i kfo ./kube-fluentd-operator/charts/log-router \
  --set rbac.create=true \
  --set image.tag=v1.17.2 \
  --set image.repository=vmware/kube-fluentd-operator
```
