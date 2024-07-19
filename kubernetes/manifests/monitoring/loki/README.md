We use [Grafana Loki](https://grafana.com/oss/loki/) and [Grafana Alloy](https://grafana.com/oss/alloy-opentelemetry-collector/) for logging, both deployed through [Helm](https://helm.sh/)

# Loki
We use the `loki_values.yaml` file to deploy the `grafana/loki` Helm chart.

Once this is deployed, the `loki-gateway.loki.svc.cluster.local` service will point to a Loki replica.

```sh
$ helm repo add grafana https://grafana.github.io/helm-charts
$ helm repo update
$ helm upgrade --install -n loki --values loki_values.yaml loki grafana/loki
```

# Alloy

```sh
$ helm upgrade --install -n loki --values alloy_values.yaml alloy grafana/alloy
```
Alloy will begin automatically shipping logs to Loki.
