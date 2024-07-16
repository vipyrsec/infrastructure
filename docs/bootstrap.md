# Bootstrapping Dragonfly on Digital Ocean

## Prerequisites

You will need:

* [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) configured with a...
* [Digital Ocean Personal Access Token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) with at least the following scopes:
  * kubernetes (2): create, delete
  * If replacing an existing cluster:
    * load\_balancer (1): delete
* `PWD` set to the root of this repo
* [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
* [`helm`](https://helm.sh/docs/intro/install/)

## Create the cluster in Digital Ocean
```bash
doctl k8s cluster create \
  <cluster-name> \
  --size s-2vcpu-2gb \
  --count 2 \
  --region nyc3
```

Adjust `size` and `count` as needed. See [`doctl kubernetes cluster create
docs`](https://docs.digitalocean.com/reference/doctl/reference/kubernetes/cluster/create/)
for more options.

## Apply `cert-manager` CRDs

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml
```

## Install the Helm Chart for `ingress-nginx` and `cert-manager`

```bash
helm upgrade vipyrsec ./kubernetes/chart --install
```

## Apply manifests and secrets

Secrets are not included in this repo; you will need to create your own.

```bash
kubectl apply -f ./kubernetes/manifests -R
```

## If access over the internet is required, create a DNS A Record to use the new load balancer

## If replacing an existing cluster, destroy old resources

```bash
doctl k8s cluster delete <name>
doctl compute load-balancer delete <id>
```
