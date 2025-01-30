#!/bin/bash

while getopts n: ch; do
  case $ch in
  n) opt_namespace=$OPTARG ;;
  *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))

infraenv_name=$1
shift
[[ -z "$infraenv_name" ]] && exit 1

set -e

discovery_url=$(kubectl ${opt_namespace:+-n ${opt_namespace}} get infraenv "$infraenv_name" -o jsonpath='{ .status.isoDownloadURL }')

for node in "$@"; do
  echo "$node: detach all ports"
  openstack esi node network detach --all "$node" ||:
  echo "$node: attach to provisioning network"
  openstack esi node network attach --network provisioning "$node"
  echo "$node: set deploy interface"
  openstack baremetal node set --instance-info deploy_interface=ramdisk "$node"
  echo "$node: set boot_iso url"
  openstack baremetal node set --instance-info boot_iso="$discovery_url" "$node"
  echo "$node: deploy node"
  openstack baremetal node deploy "$node"
done
