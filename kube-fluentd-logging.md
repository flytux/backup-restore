# Kube Fluentd Logging Operator

- elasticsearch and minio as sink
- control namespace logging with configmaps
- find tuning fluentd options with fluentd stanard functions
https://github.com/vmware/kube-fluentd-operator

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
---

```bash

cat << EOF >> fluent.conf
# Elastic search match
<match **>
      @type elasticsearch
      @id logging-es-out
      exception_backup true
      fail_on_detecting_es_version_retry_exceed true
      fail_on_putting_template_retry_exceed true
      host quickstart-es-http
      index_name logging-local
      password EC8B4HU236RIQ8UDZh92F0Z6
      port 9200
      reload_connections true
      scheme https
      ssl_verify false
      ssl_version TLSv1_2
      user elastic
      utc_index true
      verify_es_version_at_startup true
      <buffer tag,time>
        @type file
        chunk_limit_size 8MB
        path /buffers/local-es-output.*.buffer
        retry_forever true
        timekey 1m
        timekey_use_utc true
        timekey_wait 30s
</match>
EOF
# create elastic output
kubectl create configmap fluentd-config -n logging --from-file=fluent.conf=fluent.conf

# create sample logger
cat << EOF >> logger-test.yml
---
apiVersion: v1
kind: Pod
metadata:
  name: jpetfile
  namespace: kfo-test
  labels:
    msg: exceptions-file
    app: jpetfile
spec:
  containers:
  - image: ellerbrock/alpine-bash-curl-ssl:0.3.0
    name: jpetstore
    env:
    - name: EXCEPTION_URL
      value: https://gist.githubusercontent.com/jvassev/59d7616d601d9c19e23b328e591546d8/raw/22e32c7545b5f02f2df1cfaf621d91895c4d28b1/java.log
    command:
    - bash
    - -c
    - while true; do echo Tue, 01 Aug 2023 18:13:45 +0900 [ERROR] "Internal error file $((var++)) " && curl -Lsk $EXCEPTION_URL; sleep 5; done
    volumeMounts:
    - mountPath: /var/log
      name: logs
  volumes:
  - name: logs
    emptyDir: {}

---
apiVersion: v1
kind: Pod
metadata:
  name: stdout-logger
  namespace: kfo-test
  labels:
    msg: stdout
spec:
  containers:
  - image: ubuntu
    name: main
    command:
    - bash
    - -c
    - while true; do echo Tue, 01 Aug 2023 18:13:45 +0900 [INFO] "Random msg number $((var++)) to stdout"; sleep 2; done

---
apiVersion: v1
kind: Pod
metadata:
  name: hello-logger
  namespace: kfo-test
  labels:
    test-case: a
    msg: hello
spec:
  containers:
  - image: ubuntu
    name: greeter
    command:
    - bash
    - -c
    - while true; do echo Tue, 01 Aug 2023 18:13:45 +0900 [INFO] "Random hello number $((var++)) to file"; sleep 2; [[ 4 == 0 ]] && :> /var/log/hello.log ;done > /var/log/hello.log
    volumeMounts:
    - mountPath: /var/log
      name: logs
    - mountPath: /host-root
      name: root
  volumes:
  - name: logs
    emptyDir: {}
  - name: root
    hostPath:
      path: /

---
apiVersion: v1
kind: Pod
metadata:
  name: welcome-logger
  namespace: kfo-test
  labels:
    test-case: b
    msg: welcome
spec:
  containers:
  - image: ubuntu
    name: test-container
    command:
    - bash
    - -c
    - while true; do echo Tue, 01 Aug 2023 18:13:45 +0900 [INFO] "Random welcome number $((var++)) to file"; sleep 2; [[ 5 == 0 ]] && :> /var/log/welcome.log ;done > /var/log/welcome.log
    volumeMounts:
    - mountPath: /var/log
      name: logs
    - mountPath: /host-root
      name: root
  volumes:
  - name: logs
    emptyDir: {}
  - name: root
    hostPath:
      path: /
EOF
```
---

```bash
# create test logger config
cat << EOF >> fluent.conf
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: kfo-test
data:
  fluent.conf: |
    <source>
      @type mounted-file
      path /var/log/hello.log
      labels msg=hello
    </source>
    <source>
      @type mounted-file
      path /var/log/welcome.log
      labels msg=welcome, _container=test-container
    </source>
    <source>
      @type mounted-file
      path /var/log/jpetfile.log
      labels app=jpetfile
    </source>
    <filter $labels(app=jpetstore)>
      @type detect_exceptions
      languages java
    </filter>
    <filter $labels(app=jpetfile)>
      @type detect_exceptions
      languages java
    </filter>
    <match **>
     @type elasticsearch
     include_tag_key false

     host "quickstart-es-http"
     scheme "https"
     port "9200"
     user "elastic"
     password "EC8B4HU236RIQ8UDZh92F0Z6"

     logstash_format true

     reload_connections "true"
     logstash_prefix "kfo-logger-test"
     buffer_chunk_limit 1M
     buffer_queue_limit 32
     flush_interval 1s
     max_retry_wait 30
     disable_retry_limit
     num_threads 8
    </match>
EOF

kubectl create configmap fluentd-config -n kfo-test --from-file=fluent.conf=fluent.conf


