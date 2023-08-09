# Bootstrapping a Kubernetes cluster

## Create namespaces

```bash
kubectl apply -f kubernetes\manifests\cert-manager\namespace.yaml
kubectl apply -f kubernetes\manifests\discord\namespace.yaml
kubectl apply -f kubernetes\manifests\dragonfly\namespace.yaml
```

## Install the Helm Chart to get all the dependencies

```bash
helm install -f kubernetes\chart\production.yaml vipyrsec kubernetes\chart\
```

## Apply the Discord bot deployment

```bash
kubectl apply -f kubernetes\manifests\discord\bot
```

## Apply the Dragonfly Mainframe deployment

```bash
kubectl apply -f kubernetes\manifests\dragonfly\client
```

After the mainframe ingress is created, you will need create the DNS records before deploying the client.

## Apply the Dragonfly client deployment

```bash
kubectl apply -f kubernetes\manifests\dragonfly\mainframe
```
