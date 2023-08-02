# Create logging > output > flow

- Create logging with clustom images
- Create output sink elastic and s3 store
- Create flow filters handling exeption multilines
- Multi logging setting for different settings
- hostfile tailers

---
- Install elasticsearch
- Intall minio
- Install logging-operator
- Install logging test applications
- Install logging > output > flow
- Check log in elasstic and s3

```bash
-- 
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: logging-dev
spec:
  fluentbit: 
    image:
      repository: fluent/fluent-bit
      tag: 2.1.8
  fluentd:
    image:
      repository: kube-logging/fluentd
      tag: v1.15-ruby3
    logLevel: debug
    configReloaderImage:
      repository: kube-logging/config-reloader
      tag: v0.0.5
  controlNamespace: elastic-system # where fluent-bit ds and fluentd lives and no logging flow/output lives
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
  name: es-output
spec:
  elasticsearch:
    host: elasticsearch-master.elastic-system.svc.cluster.local
    port: 9200
    scheme: https
    ssl_verify: false
    ssl_version: TLSv1_2
    user: elastic
    password:
      valueFrom:
        secretKeyRef:
          name: elasticsearch-master-credentials
          key: password
    buffer:
      timekey: 1m
      timekey_wait: 30s
      timekey_use_utc: true
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
  name: s3-output
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
    force_path_style: 'true' # requires for minio and s3 compatibles
    path: app-log/${tag}/%Y/%m/%d/
    s3_bucket: hro-app-log
    s3_endpoint: https://kr.object.private.fin-ncloudstorage.com
    s3_region: kr-standard
    buffer:
      timekey: 1m
      timekey_wait: 30s
      timekey_use_utc: true
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: dev-flow
spec:
  filters:
  - stdout:
      output_type: json
  - detectExceptions: # where exception handles with fluentd plug-in
      multiline_flush_interval: "0.1"
  - parser:
      parse:
        type: json
      remove_key_name_field: false
      reserve_data: true
  localOutputRefs:
  - es-output
  - s3-output
  match:
  - select:
      labels:
        tier: backend
---
apiVersion: v1
data:
  password: 
  username: 
kind: Secret
metadata:
  name: elasticsearch-master-credentials
---
apiVersion: v1
data:
  access_key_id: 
  secret_access_key: 
kind: Secret
metadata:
  name: s3-auth
type: Opaque
```
