# Bootstrapping a Kubernetes cluster

## Override the secrets as needed

```bash
helm secrets edit ./chart/secrets/discord/local.secrets.enc.yaml
helm secrets edit ./chart/secrets/dragonfly/local.secrets.enc.yaml
```

## Override the values as needed

```bash
${EDITOR} ./chart/local.values.yaml
```

## Install the Helm Chart to get all the dependencies

```bash
helm upgrade vipyrsec ./chart \
    -n vipyrsec --create-namespace \
    --install \
    -f ./chart/local.values.yaml \
    -f secrets://./chart/secrets/discord/secrets.enc.yaml \
    -f secrets://./chart/secrets/discord/local.secrets.enc.yaml \
    -f secrets://./chart/secrets/dragonfly/secrets.enc.yaml \
    -f secrets://./chart/secrets/dragonfly/local.secrets.enc.yaml
```
