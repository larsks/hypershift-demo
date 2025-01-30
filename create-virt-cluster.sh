#!/bin/bash

clustername=$1
shift
[[ -z "$clustername" ]] && exit 1

kubectl apply -f- <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: clusters-$clustername
EOF

hcp create cluster kubevirt \
    --name="$clustername" \
    --node-pool-replicas=2 \
    --memory=8Gi \
    --pull-secret=pull-secret.txt \
    --etcd-storage-class=lvms-vg1 \
    --ssh-key larsks.pub \
    --namespace clusters \
    --control-plane-availability-policy HighlyAvailable \
    --release-image=quay.io/openshift-release-dev/ocp-release:4.17.9-multi \
    "$@"
