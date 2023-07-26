- Get secret from cluster and create in other cluster

```bash
k get secret hero-reg -n argo-system -o yaml | sed '/namespace:/d' | k apply -f -n cattle-system
```
