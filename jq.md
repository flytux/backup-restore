- Get velero backup json

```bash
# Sample json from velero backup get

$ velero backup get -l ns=argo-system -o json  | jq .

{
  "kind": "BackupList",
  "apiVersion": "velero.io/v1",
  "metadata": {
    "resourceVersion": "136694921"
  },
  "items": [
    {
      "kind": "Backup",
      "apiVersion": "velero.io/v1",
      "metadata": {
        "name": "argo-system-2023-07-25-053437",
        "namespace": "velero",
        "uid": "894752a0-3166-4185-a7e1-ed2847c56b0d",
        "resourceVersion": "136544158",
        "generation": 4,
        "creationTimestamp": "2023-07-25T05:34:38Z",
        "labels": {
          "ns": "argo-system",
          "velero.backup.period": "weekly",
          "velero.io/storage-location": "default"
        },
        "annotations": {
          "velero.io/source-cluster-k8s-gitversion": "v1.24.10",
          "velero.io/source-cluster-k8s-major-version": "1",
          "velero.io/source-cluster-k8s-minor-version": "24"
	}
      },
      "spec": {
        "metadata": {},
        "includedNamespaces": [
          ""
        ],
        "ttl": "720h0m0s",
        "hooks": {},
        "storageLocation": "default",
        "defaultVolumesToFsBackup": false,
        "csiSnapshotTimeout": "10m0s",
        "itemOperationTimeout": "1h0m0s"
      },
      "status": {
        "version": 1,
        "formatVersion": "1.1.0",
        "expiration": "2023-08-24T05:34:38Z",
        "phase": "Completed",
        "startTimestamp": "2023-07-25T05:34:38Z",
        "completionTimestamp": "2023-07-25T05:35:01Z"
      }
    },
    {
      "kind": "Backup",
      "apiVersion": "velero.io/v1",
      "metadata": {
        "name": "argo-system-2023-07-25-134225",
        "namespace": "velero",
        "uid": "e4bacc56-0102-4517-bb1d-d8e269adba50",
        "resourceVersion": "136501878",
        "generation": 4,
        "creationTimestamp": "2023-07-25T04:42:25Z",
        "labels": {
          "ns": "argo-system",
          "velero.backup.period": "weekly",
          "velero.io/storage-location": "default"
        },
        "annotations": {
          "velero.io/source-cluster-k8s-gitversion": "v1.24.10",
          "velero.io/source-cluster-k8s-major-version": "1",
          "velero.io/source-cluster-k8s-minor-version": "24"
        }
      },
      "spec": {
        "metadata": {},
        "includedNamespaces": [
          ""
        ],
        "ttl": "720h0m0s",
        "hooks": {},
        "storageLocation": "default",
        "defaultVolumesToFsBackup": false,
        "csiSnapshotTimeout": "10m0s",
        "itemOperationTimeout": "1h0m0s"
      },
      "status": {
        "version": 1,
        "formatVersion": "1.1.0",
        "expiration": "2023-08-24T04:42:25Z",
        "phase": "Completed",
        "startTimestamp": "2023-07-25T04:42:25Z",
        "completionTimestamp": "2023-07-25T04:42:47Z"
      }
    }
  ]
}
```
---
- select old backup name

```bash

# Get items array, sort by creationTimestamp, filter 1st item, get name from metadata

velero backup get -l ns=argo-system -o json | jq '.items | sort_by(.metadata.creationTimestamp)[0] | .metadata.name'
  

