#!/bin/bash

kubectl "$@" get agents -o name | while read -r agent; do
  kubectl "$@" patch "$agent" --type json --patch-file /dev/stdin <<EOF
[{"op": "replace", "path": "/spec/approved", "value": true}]
EOF
done
