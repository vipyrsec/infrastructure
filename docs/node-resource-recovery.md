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
The telemetry count rules expect **three workers per production/staging cluster**.
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

## September 14 rollout updates

The first staging rollout proved the two-node pool could not schedule the bot
with the observed-memory requests: nodes already reserved 1234 and 1346 MiB of
1465 MiB allocatable memory. A temporary bot request of 192 MiB restored service
while a third `s-1vcpu-2gb` node was provisioned in each environment. Restore the
256 MiB request after capacity is Ready. No existing nodes were removed.

Both pools now have a desired count of three. Telemetry alerts expect three
healthy workers. The added nodes provide scheduling headroom; they do not replace
measurement of host overhead or workload tuning.

Image parity and the new production OpenGrep worker are authorized as part of
this rollout. Environment-specific endpoints and credentials remain distinct.
The production worker mirrors staging's one `apps-s-1vcpu-1gb` component with one
thread and one package per batch. The existing YARA worker stays at one
`apps-s-1vcpu-0.5gb` instance in each App.

Staging's old worker still packed both CoreDNS replicas and metrics-server after
scale-out. Its Alloy replacement could not reserve 256 MiB. Restart metrics-server
with its existing rolling strategy and image so the scheduler can place its
replacement using the new capacity, freeing the collector's node-local budget.

## Verified rollout state at 17:24 UTC

Merged infrastructure PRs #189 and #190, bot PRs #340 and #341,
Mainframe PR #423, and OpenGrep worker PR #9. Bot and Mainframe are running the same verified
registry digests in both environments, with zero restarts on their new pods:

| Component | Digest |
| --- | --- |
| Bot | `sha256:4ad61264d725efd012d025d7dd397cb49c8de482821f71b3829f2e6d61fb3d24` |
| Mainframe | `sha256:86a1e77676043b6495d1930bd08c5b93aff5a79c90493472da5070a03e65c865` |
| OpenGrep | `sha256:996a3e7239f39d383ed8ec5defc9e3b225c3ef03c9677ef55c1aeb2674c04a38` |
| Existing YARA workers | `sha256:62a7b64d7a0d0967fe2dc581ce8b061169aeb5a27f99c4f7f730403b5b90a028` |

Staging's OpenGrep App deployment
`1224cb95-8b26-4c79-8752-5e772adb12e3` is ACTIVE on the new digest. The update
changed only the image and preserved all encrypted App settings unchanged. Its
YARA worker kept the existing digest. Registry digests were checked against
published CI output; the OpenGrep signing workflow completed successfully.

Production completed the additive migrations through `a71dc40e9b82`. Both APIs
serve normal scan traffic successfully. The staging bot completed the OpenGrep
publication lifecycle against the updated API. Production OpenGrep remains
explicitly disabled until the new worker's credentials can be configured.

The bot uses the full 256 MiB request in both environments. The production bot
and Mainframe now occupy different workers. Reporter retains its production-only
role and image; its resource update completed. Both Alloy DaemonSets have three
ready replicas. Prometheus reports three healthy node scrapes and three healthy
kubelet/cAdvisor scrapes per environment, with pod/container labels present.
Live PostgreSQL collector settings were preserved during the collector patches.

At 17:24 UTC all six nodes had 34–49% available memory and load averages below
0.6. The previously distressed production node had 34% available memory and a
0.25 one-minute load, compared with approximately 4% available memory and load
40 during investigation. Five-minute memory stall ratios were below 0.3% on the
available series. These are immediate post-rollout observations, not a long-term
capacity guarantee.

Grafana's existing Recreate deployment was restarted after updating both alert
ConfigMaps. Alert provisioning completed and the alert scheduler started. The
existing folder migration logged a duplicate-folder cleanup failure because the
folder contains 16 alert rules; the folder was retained and provisioning finished.
No rule or folder was deleted manually.

## Remaining explicitly blocked steps

Automatic approval review rejected credential access for a bot-token diagnostic
and a production Kubernetes upgrade. No bypass or indirect credential extraction
was attempted. Complete these steps only after explicit approval:

1. Provision the production OpenGrep component in
   `dragonfly-scanner-production` (`847aeafc-4716-433c-add8-adb668d49dd6`). Use the
   verified OpenGrep digest above, name `opengrep-shadow`, one
   `apps-s-1vcpu-1gb` instance, `DRAGONFLY_THREADS=1`, `DRAGONFLY_BULK_SIZE=1`, and
   `DRAGONFLY_BASE_URL=https://dragonfly.vipyrsec.com`. Configure a production
   Cloudflare Access service identity in encrypted runtime variables
   `DRAGONFLY_CF_ACCESS_CLIENT_ID` and `DRAGONFLY_CF_ACCESS_CLIENT_SECRET`.
   Record its origin and expiration after provisioning; neither exists yet.
2. Apply `kubernetes/environments/production/dragonfly/opengrep-shadow-config.yaml`
   and restart Mainframe, then the bot. Verify job leases, submitted results,
   and thread publication without altering YARA scores or backfilling history.
3. Upgrade production from `1.34.8-do.3` to staging's `1.34.10-do.4` using the
   supported DigitalOcean cluster upgrade. That exact upgrade was offered by
   DigitalOcean. Do not patch managed kube-proxy images directly. Expect rolling
   node replacement and possible brief workload disruption.
4. Investigate the staging threat-intelligence feed's GitHub HTTP 401 using an
   explicitly authorized credential check. Production logs show that this feed
   is disabled because its token is unconfigured. Do not reuse a personal GitHub
   token or claim the feed is healthy without checking the intended service token.

The complete user-requested end state has not been reached while these steps are
pending. Existing matching Kubernetes infrastructure images were preserved;
managed kube-proxy remains v1.34.8 in production and v1.34.10 in staging.

At 17:24:56 UTC the updated staging OpenGrep worker completed a real scan of
`people-context` version `1.2.1` in 12.212 seconds, reporting two findings and
`partial=false`, then resumed its normal idle polling.
