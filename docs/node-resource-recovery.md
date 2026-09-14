# Node resource and telemetry recovery

The September 13–14, 2026 incidents exposed memory pressure, unaccounted workload
requests, and missing per-container metrics. The production bot, Mainframe, and
reporter together used approximately 500 MiB during investigation, while Alloy,
Cilium, other pods, and host services consumed the remaining headroom.

## Resource budget

| Workload | CPU request | Memory request | Memory limit |
| --- | --- | --- | --- |
| Bot | 25m | 256Mi | 512Mi |
| Mainframe | 50m | 256Mi | 512Mi |
| Reporter | 10m | 96Mi | 192Mi |
| Alloy, per worker | 50m | 256Mi | 512Mi |

CPU limits are omitted to allow short bursts without introducing throttling.
Requests include headroom above the observed application working sets. Memory
limits bound individual growth, but do not reserve that much memory or guarantee
that all workloads can peak together. Review the new container history before
tuning these values further.

The bot prefers a different node from Mainframe across the `discord` and
`dragonfly` namespaces. This preference allows scheduling during a one-node outage.
Its Recreate strategy prevents two active bots during an upgrade, at the cost of
a brief disconnect. Mainframe and reporter retain their existing update strategy.

## Collection and alerts

Each Alloy discovers only pods on its own node, using the chart's existing
`HOSTNAME=spec.nodeName` environment variable. Log collection remains enabled for
all local pods. HTTP metrics collection accepts only the explicitly named metrics
ports, including Mainframe's newly named `http-metrics` port. New instrumented
services must expose a matching port name; ordinary HTTP, DNS, and webhook ports
are not metrics targets.

Container metrics come from the node's kubelet cAdvisor endpoint through the
authenticated Kubernetes API proxy, with service-account CA verification. The
existing Alloy role already grants `nodes/proxy`; no new role grants or privileged
host mounts are introduced. This replaces the embedded cAdvisor exporter, which
exposed root-cgroup metrics without usable pod/container identities.

Existing Grafana environment contact points gain rules for less than 10% available
node memory, more than 10% memory stall time, and missing node/container telemetry.
The telemetry count rules expect **two workers per production/staging cluster**.
Update both counts when pool size changes. A missing series evaluates as zero
healthy workers rather than implying zero utilization. Rules wait five minutes
before firing and retain the environment's existing Discord receiver.

## Rollout

1. Confirm the DigitalOcean `vipyr` context and the explicit Kubernetes context.
2. Capture the current Deployment, DaemonSet, collector ConfigMap, and Grafana
   provisioning specifications for rollback. Keep captured values outside Git.
3. Compare live configuration with this PR. Live images and PostgreSQL collector
   settings differ from repository defaults: do not perform a blanket Helm or
   manifest apply that reverts those unrelated settings.
4. In staging first, apply the resource fields and bot placement/update strategy
   while preserving live images, environment sources, and security settings.
   Add Mainframe's metrics port name with its resource change. Roll one workload
   at a time and wait for readiness; stop on Pending pods or memory-limit kills.
5. Update the live Alloy configuration with only the local discovery, metrics-port
   selection, and kubelet scrape changes. Preserve existing PostgreSQL collectors
   and destinations. Apply the Alloy resource budget separately and wait for its
   DaemonSet rollout.
6. Verify two healthy `up{job="prometheus.scrape.cadvisor"}` series, distinct
   `container_memory_working_set_bytes` series with `namespace`, `pod`, and
   `container` labels, continuing Mainframe metrics, and logs from both nodes.
   Check that HTTP-to-HTTPS scrape errors have stopped.
7. Repeat the bounded rollout in production only after staging is healthy.
8. Load the added Grafana rules after both environments expose the new metrics.
   Alert provisioning files are mounted with `subPath`, so changing a ConfigMap
   alone does not refresh the mounted files. Use the established Grafana rollout
   procedure, preserving its single-writer Recreate strategy and existing image.
9. Watch scheduling, OOM/restart counters, available memory, memory PSI, and bot
   polling. Successful API polls alone do not prove node pressure is resolved.

Rollback restores only the changed resource, placement, and collection fields
from the captured specifications. The bot application fix is a separate release;
these infrastructure changes must not implicitly change its image.

## Validation

Run the workspace `prek-workspace run --all-files`, strict Helm lint/rendering,
and `zizmor --pedantic .github/workflows`. Alloy 1.7.5 has no `validate` command:
use its `fmt --test` parser, then confirm component health and actual series during
staging rollout. The kubelet endpoint was independently checked for bot container
labels before authoring the configuration.

The added Grafana PromQL was checked with `promtool check rules --lint=all
--lint-fatal`. Synthetic PromQL tests cover two workers, a missing worker, all
metrics absent, and environment isolation. Promtool test storage must use an
isolated temporary directory, never the live Prometheus data directory.
