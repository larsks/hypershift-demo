# Hosted Control Planes (neè HyperShift)

---

> [!WARNING]
> The scripts in this repository are what I used during our meetings during the
> week of 1/27/2025-1/30/2025. They are intended to get things running and
> demonstrate some of the necessary steps. They are **not** meant to represent
> best (or even recommended) practice.

---

[Hosted Control Planes](https://docs.openshift.com/container-platform/4.14/hosted_control_planes/index.html) -- the product formerly known as HyperShift -- allows you to create containerized OpenShift control planes. This has a number of advantages:

1. More efficient use of hardware resources

2. Rapid deployment of new clusters

3. Separating the cluster administrator from the hardware administrator

    (No MachineConfig operator on hosted cluster; node configuration managed through NodePool on management cluster.)

## Creating a new Hosted Cluster

### Create the control plane

You need:

- A HostedCluster resource
- A NodePool (which at the moment must start with 0 nodes)
- An ssh public key
- A pull secret
- An etcd encryption secret

You can create these using the `hcp` command line:

```
hcp create cluster agent \
  --agent-namespace clusters \
  --base-domain int.massopen.cloud \
  --name vcluster2 \
  --pull-secret secrets/pull-secret.txt \
  --ssh-key id_rsa.pub \
  --release-image quay.io/openshift-release-dev/ocp-release@sha256:03cc63c0c48b2416889e9ee53f2efc2c940323c15f08384b439c00de8e66e8aa
```

Add the `--render` flag to generate manifests on `stdout` instead of actually creating the resources in OpenShift. The above command will create:

| Resource type | Namespace | Name                          |
|---------------|-----------|-------------------------------|
| Namespace     | clusters  |
| Secret        | clusters  | vcluster2-pull-secret         |
| HostedCluster | clusters  | vcluster2                     |
| Role          | clusters  | capi-provider-role            |
| Secret        | clusters  | vcluster2-etcd-encryption-key |
| NodePool      | clusters  | vcluster2                     |

Or you can generate the manifests via some other mechanism (e.g. `kustomize`) and submit them.

The process of realizing the HostedCluster will create three namespaces:

- `clusters-vcluster2`
- `klusterlet-vcluster2`
- `vcluster2`

Cluster metadata, like the HostedCluster resource itself, Secrets, etc, are created in the `clusters` namespace.

The control plane is created in the `clusters-<clustername>` namespace, and requires around 75 pods when fully deployed:

```
$ oc -n clusters-vcluster1 get pod -o name | wc -l
74
```

Deploying the control plane takes around five minutes. You can retrieve an administrative `kubeconfig` file and the `kubeadmin` credentials from the web ui or from the appropriate Secrets in the `clusters` namespace:

```
oc -n clusters extract secret/vcluster1-admin-kubeconfig
```

The process of creating a HostedCluster also generates a ManagedCluster resource, which represents the cluster in ACM (and is the thing to which we can attach ACM policy, ArgoCD applicationsets, etc).

### Accessing the control plane

The API service service is exposed as a `NodePort` service on the management cluster:

```
$ oc -n clusters-vcluster1 get service kube-apiserver
NAME             TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kube-apiserver   NodePort   172.30.107.50   <none>        6443:30253/TCP   41d
```

The cluster creation process creates a `kubeconfig` file with the appropriate port. For example:

```
apiVersion: v1
clusters:
- cluster:
    server: https://api.vcluster1.int.massopen.cloud:30253
  name: cluster
.
.
.
```

The `api` hostname should point at one or more nodes in the management cluster.

At this point, we have a functioning control plane but there are no workloads running on the hosted cluster...

```
$ KUBECONFIG=kubeconfig oc get pod -A
NAMESPACE                    NAME               READY   STATUS    RESTARTS   AGE
openshift-network-operator   mtu-prober-w99cf   0/1     Pending   0          6m36s
```

...because there are no nodes available. One implication of this is that the web ui won't be available yet (the console and the ingress service are both cluster workloads). You will see some degraded cluster operators due primarily to the lack of an available ingress:

```
$ kubectl get co
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
console                                                                                           
csi-snapshot-controller                    4.14.10   True        False         False      83s     
dns                                        4.14.10   False       Unknown       False      82s     DNS "default" is unavailable.
image-registry                                       False       True          False      63s     Available: The deployment does not have available replicas...
ingress                                    4.14.10   True        True          False      52s     ingresscontroller "default" is progressing: IngressControllerProgressing: One or more status conditions indicate progressing: DeploymentRollingOut=True (DeploymentRollingOut: Waiting for router deployment rollout to finish: 0 out of 1 new replica(s) have been updated......
insights                                                                                          
kube-apiserver                             4.14.10   True        False         False      82s     
kube-controller-manager                    4.14.10   True        False         False      82s     
kube-scheduler                             4.14.10   True        False         False      82s     
kube-storage-version-migrator                                                                     
monitoring                                                                                        
network                                                                        True               Internal error while merging cluster configuration and operator configuration: could not apply (operator.openshift.io/v1, Kind=Network) /cluster, err: failed to apply / update (operator.openshift.io/v1, Kind=Network) /cluster: Operation cannot be fulfilled on networks.operator.openshift.io "cluster": the object has been modified; please apply your changes to the latest version and try again
node-tuning                                          False       True          False      79s     DaemonSet "tuned" has no available Pod(s)
openshift-apiserver                        4.14.10   True        False         False      82s     
openshift-controller-manager               4.14.10   True        False         False      82s     
openshift-samples                                                                                 
operator-lifecycle-manager                 4.14.10   True        False         False      78s     
operator-lifecycle-manager-catalog         4.14.10   True        True          False      88s     Deployed 4.14.0-202401151553.p0.gf5327f0.assembly.stream-f5327f0
operator-lifecycle-manager-packageserver   4.14.10   True        False         False      82s     
service-ca                                                                                        
storage                                    4.14.10   True        False         False      86s     
```

## Discovering nodes

Nodes are assigned to a HostedCluster from an InfraEnv. You could create one InfraEnv per cluster, or you can create a common InfraEnv shared by all clusters (which is what I have done on in this environment). An InfraEnv manages the node discovery process and provides things like a discovery cd image, ipxe scripts, etc. An InfraEnv requires a pull secret; You may also provide a public ssh key that can be used to log in to nodes managed by the InfraEnv.

Adding nodes is a familiar process:

- Download the discovery ISO
- Boot the nodes with the ISO
- Wait for them to register with the InfraEnv

You can get the path for the discovery ISO like this:

```
oc -n hardware-inventory get infraenv hardware-inventory -o jsonpath='{.status.isoDownloadURL}'
```

There are also options for having ACM manage the discovery process automatically utilizing the node bmc, or of provisioning nodes via an existing PXE server. You can retrieve the URL for the iPXE script from the InfraEnv:

```
oc -n hardware-inventory get infraenv hardware-inventory -o jsonpath='{.status.bootArtifacts.ipxeScript}'
```

The script will look something like:

```
#!ipxe
initrd --name initrd https://assisted-image-service-multicluster-engine.apps.hypershift1.int.massopen.cloud/images/770980f8-07d0-4824-899c-0da82a7555a5/pxe-initrd?api_key=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbmZyYV9lbnZfaWQiOiI3NzA5ODBmOC0wN2QwLTQ4MjQtODk5Yy0wZGE4MmE3NTU1YTUifQ.btTxrWWcl5Stpc7zZ448Cll_kMOGSbcS2u9iiOFSXHFfdJKB43VTXEzeuJZF9Bw1KFvV47hZ0YhbuozVxe6RjA&arch=x86_64&version=4.14
kernel https://assisted-image-service-multicluster-engine.apps.hypershift1.int.massopen.cloud/boot-artifacts/kernel?arch=x86_64&version=4.14 initrd=initrd coreos.live.rootfs_url=https://assisted-image-service-multicluster-engine.apps.hypershift1.int.massopen.cloud/boot-artifacts/rootfs?arch=x86_64&version=4.14 random.trust_cpu=on rd.luks.options=discard ignition.firstboot ignition.platform.id=metal console=tty1 console=ttyS1,115200n8 coreos.inst.persistent-kargs="console=tty1 console=ttyS1,115200n8"
boot
```

Note that this requires https support in iPXE.

Because we're performing agent-based installs, nodes are referred to as "Agents". Discovered agents need to be approved before they become available for cluster deployments:

```
oc patch agent <agent_name> --type merge --patch '{"spec": {"approved": true}}'
```

Here you can see four nodes that have been discovered by the `available-nodes` InfraEnv. Two are in use by `vcluster1`, and two are unassigned and available:

```
$ oc -n clusters get agents
NAME                                   CLUSTER     APPROVED   ROLE          STAGE
234d87fe-73a2-85ec-e57a-3a0a3c8aaf1f   vcluster1   true       worker        Done
8fc583b5-b7e7-0cf4-8068-179ea6e069e8               true       auto-assign   
b5b539f4-cca0-3f13-6a7f-dd7e6b7b8c0d   vcluster1   true       worker        Done
db54484f-3f20-d5dc-bf24-6b1d3d8f0a68               true       auto-assign   
```

## Adding nodes

We created a NodePool resource along with the HostedCluster. Initially, the NodePool has zero nodes (you can start with a populated nodepool by passing the `--nodepool-replicas` option to the `hcp` command line):

```
$ oc -n clusters get nodepool vcluster2
NAME        CLUSTER     DESIRED NODES   CURRENT NODES   AUTOSCALING   AUTOREPAIR   VERSION   UPDATINGVERSION   UPDATINGCONFIG   MESSAGE
vcluster2   vcluster2   0                               False         False        4.14.10                                      
```

We add nodes by scaling the number of replicas in the NodePool:

```
oc scale nodepool/vcluster2 --replicas 2
```

The NodePool will acquire nodes from available Agents. It takes around 15 minutes to add two bare metal nodes to the cluster.

You will continue to see degraded cluster operators because we do not have an available ingress service:

```
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
console                                    4.14.10   False       False         False      30m     RouteHealthAvailable: failed to GET route (https://console-openshift-console.apps.vcluster2.int.massopen.cloud): Get "https://console-openshift-console.apps.vcluster2.int.massopen.cloud": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
csi-snapshot-controller                    4.14.10   True        False         False      51m
dns                                        4.14.10   True        False         False      28m
image-registry                             4.14.10   True        False         False      29m
ingress                                    4.14.10   True        False         True       51m     The "default" ingress controller reports Degraded=True: DegradedConditions: One or more other status conditions indicate a degraded state: CanaryChecksSucceeding=False (CanaryChecksRepetitiveFailures: Canary route checks for the default ingress controller are failing)
insights                                   4.14.10   True        False         False      30m
kube-apiserver                             4.14.10   True        False         False      51m
kube-controller-manager                    4.14.10   True        False         False      51m
kube-scheduler                             4.14.10   True        False         False      51m
kube-storage-version-migrator              4.14.10   True        False         False      29m
monitoring                                 4.14.10   True        False         False      28m
network                                    4.14.10   True        False         False      33m
node-tuning                                4.14.10   True        False         False      34m
openshift-apiserver                        4.14.10   True        False         False      51m
openshift-controller-manager               4.14.10   True        False         False      51m
openshift-samples                          4.14.10   True        False         False      27m
operator-lifecycle-manager                 4.14.10   True        False         False      51m
operator-lifecycle-manager-catalog         4.14.10   True        False         False      51m
operator-lifecycle-manager-packageserver   4.14.10   True        False         False      51m
service-ca                                 4.14.10   True        False         False      30m
storage                                    4.14.10   True        False         False      51m
```

## Configuring an ingress address

While the API address is handled by the management cluster, the ingress address will be hosted on the hosted cluster.

We can configure the ingress ip using MetalLB.

- Install MetalLB operator
- Create MetalLB instance
- Create MetalLB resources (l2advertisement, ipaddresspool)
- Create `LoadBalancer` Service in `openshift-ingress` namespace using the MetalLB-provided address

## Destroying a hosted cluster

You can use the `hcp` cli:

```
hcp destroy cluster agent --name vcluster2
```

Or you can destroy the HostedCluster and ManagedCluster resources by hand.

The process takes around 10-15 minutes to complete.

## Things that didn't fit elsewhere

- Cluster upgrades will utilize available nodes during upgrade process
- `hostedcluster.spec.release` controls openshift version in control plane
- `nodepool.spec.release` controls openshift version on nodes

## See also

### Official documentation

- https://hypershift-docs.netlify.app
- https://docs.openshift.com/container-platform/4.14/hosted_control_planes/index.html
- https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.9/html/clusters/cluster_mce_overview#hosted-sizing-guidance

### Relevant repositories

- https://github.com/larsks/hypershift-clusters
- https://github.com/larsks/hypershift-test-apps
- https://github.com/larsks/nerc-ocp-config/tree/cluster/hypershift
