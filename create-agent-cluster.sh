#!/bin/bash

clustername=$1
shift

[[ -z "$clustername" ]] && exit 1

tee -a "${clustername}-extra-manifests.yaml" <<EOF | kubectl apply -f- >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: clusters-$clustername
EOF

hcp create cluster agent \
  --name="$clustername" \
  --pull-secret=pull-secret.txt \
  --agent-namespace=hardware-inventory \
  --base-domain=int.massopen.cloud \
  --api-server-address=api."$clustername".int.massopen.cloud \
  --etcd-storage-class=lvms-vg1 \
  --ssh-key larsks.pub \
  --namespace clusters \
  --control-plane-availability-policy HighlyAvailable \
  --release-image=quay.io/openshift-release-dev/ocp-release:4.17.9-multi \
  "$@"
