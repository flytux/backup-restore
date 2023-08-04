# Cluster Logging with Host Files

- Mount Host Volumes to Fluentbit
- Tail Files from head with InputTail with Multiline parser
- Detect Exception from Flows
- Loggging with timestamp via logstash format
 
---
```bash
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: logging-dev
spec:
  controlNamespace: cattle-logging-system
  fluentbit:
    extraVolumeMounts:
    - destination: /hro/nas_dev
      readOnly: true
      source: /hro/nas_dev
    image:
      imagePullSecrets:
      - name: hero-reg
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/fluent/fluent-bit
      tag: 2.1.4-debug
    inputTail:
      Path: /hro/nas_dev/dev/hro_app/core-com-api-dev/log/*.log
      Read_From_Head: on
      multiline.parser:
        - java
    logLevel: debug
  fluentd:
    configReloaderImage:
      imagePullSecrets:
      - name: hero-reg
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/kube-logging/config-reloader
      tag: v0.0.5
    image:
      imagePullSecrets:
      - name: hero-reg
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/kube-logging/fluentd
      tag: v1.15-ruby3
    logLevel: debug
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: clusterflow-dev
spec:
  filters:
  - detectExceptions: 
      multiline_flush_interval: "1"  
  globalOutputRefs: 
  - clusteroutput-es
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
  name: clusteroutput-es
spec:
  elasticsearch:
    buffer:
      timekey: 1m
      timekey_use_utc: true
      timekey_wait: 30s
    logstash_format: true
    logstash_prefix: "app-core-dev"
    host: elasticsearch-master.elastic-system.svc.cluster.local
    password:
      valueFrom:
        secretKeyRef:
          key: password
          name: elasticsearch-master-credentials
    port: 9200
    scheme: https
    ssl_verify: false
    ssl_version: TLSv1_2
    suppress_type_name: true
    user: elastic
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
  name: clusteroutput-s3
spec:
  s3:
    aws_key_id:
      valueFrom:
        secretKeyRef:
          key: access_key_id
          name: s3-auth
    aws_sec_key:
      valueFrom:
        secretKeyRef:
          key: secret_access_key
          name: s3-auth
    buffer:
      timekey: 1m
      timekey_use_utc: true
      timekey_wait: 30s
    force_path_style: "true"
    path: app-log/${tag}/%Y/%m/%d/
    s3_bucket: hro-app-log
    s3_endpoint: https://kr.object.private.fin-ncloudstorage.com
    s3_region: kr-standard
```
---
- Host tailers
- Create additional fluentbit ds for Hostfile Tailers

```bash
---
apiVersion: logging-extensions.banzaicloud.io/v1alpha1
kind: HostTailer
metadata:
  name: fluent-dev
  namespace: elastic-system
spec:
  fileTailers:
  - name: error-log
    path: /hro/nas_dev/dev/hro_app/core-com-api-dev/log/core-com-api-dev-*-error.log
    disabled: false
    containerOverrides:
      image: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/fluent/fluent-bit:2.1.4-debug
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: flow-core-com-api-dev
  namespace: elastic-system
spec:
  filters: 
  - detectExceptions:
      multiline_flush_interval: "0.1"
  localOutputRefs:
    - output-core-com-api-dev
  match:
  - select:
      labels:
        app.kubernetes.io/name: host-tailer
  outputRefs:
    - output-core-com-api-dev
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
  name: output-core-com-api-dev
  namespace: elastic-system
spec:
  elasticsearch:
    buffer:
      timekey: 1m
      timekey_use_utc: true
      timekey_wait: 30s
    host: elasticsearch-master.elastic-system.svc.cluster.local
    index_name: core-com-api-dev
    password:
      valueFrom:
        secretKeyRef:
          key: password
          name: elasticsearch-master-credentials
    port: 9200
    scheme: https
    ssl_verify: false
    ssl_version: TLSv1_2
    suppress_type_name: true
    user: elastic
```
