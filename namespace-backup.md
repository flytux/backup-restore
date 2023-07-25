# Namespace backup with velero cronjob

- Label velero.backup.period=weekly
- Label velero.backup.keep=2
- Select velero backup for labeled namespaces
- Delete old backups over keep
- Create new backup for namespace

---

```bash

# Labels namespace to check velero backup

❯ k get ns argo-system -o yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: argo-system
    velero.backup.keep: "2"
    velero.backup.period: weekly
  name: argo-system

# Create Cronjob with velero cli

❯ cat backup-ns-weekly-mon-2300.yml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-ns-weekly-mon-2300
  labels:
    velero.backup.period: weekly
  namespace: velero
spec:
  concurrencyPolicy: Allow
  failedJobsHistoryLimit: 1
  jobTemplate:
    metadata:
      labels:
        velero.backup.period: weekly
    spec:
      template:
        spec:
          containers:
            - command:
                - /bin/sh
                - '-c'
                - >
            
                  for target_ns in $(kubectl get ns -l velero.backup.period=weekly -o name |
                  cut -d "/" -f 2)
            
                  do
                    num_backup=$(velero backup get -l ns=$target_ns | sed 1d | wc -l);
                    num_keep_backup=$(kubectl get ns $target_ns -o "jsonpath={.metadata.labels['velero\.backup\.keep']}")
                    num_delete=$(( num_backup - num_keep_backup + 1 ))
                    
                    echo "===" $target_ns "keeps" $num_keep_backup ", has " $num_backup " backups ==="
                    if [ $num_delete -ge 0 ]
                    then
                      for backup_name in $(velero backup get -l ns=$target_ns | sed 1d | head -$num_delete | cut -d' ' -f 1)
                      do
                        echo "Deleting old backup :" $backup_name
                        velero delete backup $backup_name --confirm
                      done
                    fi
                    echo "=== Create backup in " $target_ns "===="
                    velero backup create $target_ns-$(date +%F-%H%M%S) --include-namespaces=$targer_ns --labels ns=$target_ns --labels velero.backup.period=weekly
                  done
              image: tbd5d1uh.private-ncr.fin-ntruss.com/k8s/dev/devops/dev:v2
              imagePullPolicy: Always
              name: velero-backup
              terminationMessagePath: /dev/termination-log
              terminationMessagePolicy: File
              __active: true
          dnsPolicy: ClusterFirst
          imagePullSecrets:
            - name: hero-reg
          restartPolicy: Never
          schedulerName: default-scheduler
          serviceAccount: velero
          serviceAccountName: velero
          terminationGracePeriodSeconds: 30
  schedule: 0 23 *  *  1
  successfulJobsHistoryLimit: 1
  suspend: false

# Service Account for running velero backup
---
apiVersion: v1
automountServiceAccountToken: true
imagePullSecrets:
- name: hero-reg
kind: ServiceAccount
metadata:
  labels:
  name: velero
  namespace: velero

```
