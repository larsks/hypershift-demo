#!/bin/bash

set -e

clustername=$1
shift
[[ -z "$clustername" ]] && exit 1

http_node_port=$(kubectl --kubeconfig "$clustername"-kubeconfig get services -n openshift-ingress router-nodeport-default -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
https_node_port=$(kubectl --kubeconfig "$clustername"-kubeconfig get services -n openshift-ingress router-nodeport-default -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

kubectl apply -f- <<EOF
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${clustername}
  name: ${clustername}-apps
  namespace: clusters-${clustername}
spec:
  ports:
  - name: https-443
    port: 443
    protocol: TCP
    targetPort: $https_node_port
  - name: http-80
    port: 80
    protocol: TCP
    targetPort: $http_node_port
  selector:
    kubevirt.io: virt-launcher
  type: LoadBalancer
EOF
