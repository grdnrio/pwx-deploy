#!/bin/bash
PATH=$PATH:/bin:/usr/bin:/snap/bin/jq
export PATH

# Get current args (properly quoted)
x=$(kubectl get ds/portworx -n kube-system -o json | jq -c '.spec.template.spec.containers[0].args')
# remove tailing "]", add new argument
x="${x%]},-cluster_domain, $1]"
# apply the change
kubectl patch ds/portworx -n kube-system --type json -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/args\", \"value\":$x}]"