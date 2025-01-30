#!/bin/bash

network="$1"
shift
[[ -z "$network" ]] && exit 1

set -e

for node in "$@"; do
  echo "$node: detach node from existing network"
  openstack esi node network detach --all "$node" || :

  echo "$node: attach node to \"$network\" network"
  openstack esi node network attach --network "$network" "$node"

  echo "$node: configure node to boot from disk"
  openstack baremetal node boot device set "$node" disk --persistent
done
