# How to Bootstrap Dragonfly on Digital Ocean

## Prerequisites

You will need:

* [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) configured with a...
* [Digital Ocean Personal Access Token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) with at least the following scopes:
  * kubernetes: create, delete
  * If replacing an existing cluster:
    * load\_balancer: read, delete
* `PWD` set to the root of this repo
* [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
* [`helm`](https://helm.sh/docs/intro/install/)

## Get secrets

Create Kubernetes Secrets in the `./kubernetes/manifests` directory.

See the following list for secrets to create:

* [Bot](https://github.com/vipyrsec/bot/blob/main/README.md)
* [Mainframe](https://github.com/vipyrsec/dragonfly-mainframe/README.md)
* [Loader](https://github.com/vipyrsec/dragonfly-loader/README.md)
* [Client](https://github.com/vipyrsec/dragonfly-client-rs/README.md)

## Create the cluster in Digital Ocean
```bash
doctl k8s cluster create \
  <cluster-name> \
  --size s-2vcpu-2gb \
  --count 2 \
  --region nyc3
```

Adjust `size`, `count`, and `region` as needed. See [`doctl kubernetes cluster
create
docs`](https://docs.digitalocean.com/reference/doctl/reference/kubernetes/cluster/create/)
for more options. The cluster may take a few minutes to provision.

**Note**: `doctl k8s cluster create` sets the `kubectl` context to the newly
created cluster.

## Apply `cert-manager` CRDs

```bash
kubectl apply -f ./kubernetes/crds/cert-manager.crds.yaml
```

## Install the Helm Chart for `ingress-nginx` and `cert-manager`

```bash
helm upgrade vipyrsec ./kubernetes/chart --install
```

## Apply manifests and secrets

```bash
kubectl apply -f ./kubernetes/manifests/cert-manager/namespace.yaml
kubectl apply -f ./kubernetes/manifests/discord/namespace.yaml
kubectl apply -f ./kubernetes/manifests/dragonfly/namespace.yaml
kubectl apply -f ./kubernetes/manifests -R
```

## If access over the internet is required, create a DNS A Record to use the new load balancer

## If replacing an existing cluster, destroy old resources

```bash
doctl k8s cluster delete <name>
doctl compute load-balancer delete <id>
```
