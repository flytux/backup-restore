# Logging Operator with custom image, parser, filter and host tailers

- Logging for custom fluentbit and fluentd
- install kube-logging operator
- deploy logging, flow, output, target workload 
- custom images
- custom inputTail multiline parser
- check fluentbit / fluentd config and status logs

---

```bash

# Create logging, flow, and output
# Create namepaced flow same as log gathering targets
# Label targets with match filter
# Re-deploy fluentd and bit if log is not gathered though config is correct

---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: logging-prd
spec:
  fluentbit:
    image:
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/fluent/fluent-bit
      tag: 2.1.8-debug-parser
  fluentd:
    image:
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/kube-logging/fluentd
      tag: v1.15-ruby3
    logLevel: debug
    configReloaderImage:
      repository: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/elastic-system/kube-logging/config-reloader
      tag: v0.0.5
  controlNamespace: logging
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
 name: file-output
spec:
 file:
   path: /tmp/logs/${tag}/%Y/%m/%d.%H.%M
   append: true
   buffer:
     timekey: 1m
     timekey_wait: 10s
     timekey_use_utc: true
---
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: file-flow
spec:
  filters:
    - parser:
        remove_key_name_field: false
        reserve_data: true
        parse:
          type: json
  match:
     - select:
         labels:
           app: app-core-hro-test-prd
  localOutputRefs:
    - file-output

# check fluentbit conf
$ k get secret -n logging logging-prd-fluentbit -o yaml | grep -o -E 'fluent-bit.conf.*' | cut -d ' ' -f2 | base64 -d

# check fludentd conf
$ k get secret -n logging logging-prd-fluentd-app -o yaml | grep -o -E 'fluentd.conf.*' | cut -d ' ' -f2 | base64 -d

# Build multiline custom parser and replace parsers.conf in fluentbit docker image

$ docker build -t fluent/fluent-bit:2.1.8-debug-parser .

# Regex for multiline
https://rubular.com/r/NDuyKwlTGOvq2g

# Log sample
2023-07-29T09:31:33.871799527+09:00 stdout F 29-07-2023 00:31:33.871 [pool-4296-thread-1] INFO com.github.vspiewak.loggenerator.SearchRequest - id=64436,ip=90.0.126.162,brand=Apple,name=iPod Touch,model=iPod Touch - Bleu - Disque 64Go,category=Baladeur,color=Bleu,options=Disque 64Go,price=449.0\n

# Regex test add multiline parser to parsers.conf 
[MULTILINE_PARSER]
    name          multiline-regex-test
    type          regex
    flush_timeout 1000
    #
    # Regex rules for multiline parsing
    # ---------------------------------
    #
    # configuration hints:
    #
    #  - first state always has the name: start_state
    #  - every field in the rule must be inside double quotes
    #
    # rules |   state name  | regex pattern                  | next state
    # ------|---------------|--------------------------------------------
    rule      "start_state"   "/\s\d\d-\d\d-\d+.*/"  "cont"
    rule      "cont"          "/\sjava.*|\\tat.*/"   "cont"
