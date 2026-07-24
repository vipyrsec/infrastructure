# O11y Internal LB VIP Reconciliation

This guide exists for one job:

- the `o11y` internal load balancer IP changed
- `staging` and `prod` still point at the old IP in `coredns-custom`
- logs and metrics stop reaching `o11y`

This guide tells you exactly how to check for that problem and fix it.

## What you are fixing

`staging` and `prod` do **not** use a private DNS service.

Instead, they use the `coredns-custom` ConfigMap to force these names to the current internal `o11y` load balancer IP:

- `prom.vipyrsec.com`
- `loki.vipyrsec.com`
- `grafana.vipyrsec.com`

If the `o11y` internal load balancer is recreated and gets a new private IP, those overrides become stale.

When that happens:

- `staging` and `prod` still resolve the old IP
- Alloy keeps trying to send to the old IP
- observability ingestion breaks

## What you need before you start

You need all of these:

1. A shell in the `infrastructure` repo.
2. `kubectl` installed.
3. `rg` installed.
4. Working kube contexts for:
   - `do-sfo3-o11y`
   - `do-sfo3-staging`
   - `do-sfo3-prod`

If any of those are missing, stop and fix that first.

## Where the helper script lives

Script path:

`/home/rem/github/vipyrsec/infrastructure/scripts/reconcile-o11y-internal-vip.sh`

## Step 1: Open the repo

Run:

```bash
cd /home/rem/github/vipyrsec/infrastructure
```

## Step 2: Make sure the script exists

Run:

```bash
ls -l ./scripts/reconcile-o11y-internal-vip.sh
```

You should see the script in the output.

If you do not see it, stop.

## Step 3: Make the script executable

Run:

```bash
chmod +x ./scripts/reconcile-o11y-internal-vip.sh
```

## Step 4: Run the script in dry-run mode first

Run:

```bash
./scripts/reconcile-o11y-internal-vip.sh
```

Important:

- Do **not** start with `--apply`
- Dry-run is there so you can see what the script thinks the current `o11y` VIP is

## Step 5: Read the dry-run output

The script will print:

- the current internal `o11y` VIP
- the live `coredns-custom` contents for `staging`
- the live `coredns-custom` contents for `prod`

You are looking for this:

- if all three host entries already point at the same `o11y` VIP, you do **not** need to repair anything
- if `staging` or `prod` still point at some older IP, the entry is stale and you should continue

## Step 6: Apply the fix

Run:

```bash
./scripts/reconcile-o11y-internal-vip.sh --apply
```

What this does:

1. Reads the live internal `o11y` LB IP from:
   - context `do-sfo3-o11y`
   - namespace `default`
   - service `vipyrsec-ingress-nginx-controller`
2. Rewrites `coredns-custom` in:
   - `do-sfo3-staging`
   - `do-sfo3-prod`
3. Restarts CoreDNS in both clusters
4. Waits for both CoreDNS rollouts to finish
5. Verifies that all three hostnames resolve to the new VIP in both clusters

## Step 7: If the script succeeds

You are not done yet.

You still need to confirm that ingestion is actually healthy.

Run these commands exactly:

```bash
kubectl --context do-sfo3-o11y -n prometheus exec prometheus-7454cf6864-fpmvm -- promtool query instant http://localhost:9090 'count(up{cluster="staging",job=~".*postgres.*"})'
```

```bash
kubectl --context do-sfo3-o11y -n prometheus exec prometheus-7454cf6864-fpmvm -- promtool query instant http://localhost:9090 'count(up{cluster="prod",job=~".*postgres.*"})'
```

Healthy output should show a numeric result instead of an empty vector.

## Step 8: Check that the endpoints are reachable privately

Run these commands.

From `staging`:

```bash
kubectl --context do-sfo3-staging -n default run prom-ready-staging --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://prom.vipyrsec.com/-/ready'
```

```bash
kubectl --context do-sfo3-staging -n default run loki-ready-staging --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://loki.vipyrsec.com/ready'
```

```bash
kubectl --context do-sfo3-staging -n default run grafana-login-staging --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://grafana.vipyrsec.com/login'
```

From `prod`:

```bash
kubectl --context do-sfo3-prod -n default run prom-ready-prod --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://prom.vipyrsec.com/-/ready'
```

```bash
kubectl --context do-sfo3-prod -n default run loki-ready-prod --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://loki.vipyrsec.com/ready'
```

```bash
kubectl --context do-sfo3-prod -n default run grafana-login-prod --rm -i --restart=Never --image=curlimages/curl --command -- sh -lc 'curl -sk -o /dev/null -w "%{http_code}\n" https://grafana.vipyrsec.com/login'
```

Expected results:

- Prometheus: `200`
- Loki: `404` on `/ready` is acceptable and still proves reachability
- Grafana: `200`

## What to do if the script fails

Do not guess.

Read the error and follow this order:

1. Check that the `o11y` Service has a VIP at all.

Run:

```bash
kubectl --context do-sfo3-o11y -n default get svc vipyrsec-ingress-nginx-controller -o yaml
```

If `.status.loadBalancer.ingress[0].ip` is empty, stop.

The `o11y` internal LB itself is not ready yet.

2. Check that CoreDNS restarted successfully.

Run:

```bash
kubectl --context do-sfo3-staging -n kube-system rollout status deployment coredns --timeout=180s
```

```bash
kubectl --context do-sfo3-prod -n kube-system rollout status deployment coredns --timeout=180s
```

If either rollout fails, stop and fix CoreDNS before doing anything else.

3. Check what `coredns-custom` actually contains.

Run:

```bash
kubectl --context do-sfo3-staging -n kube-system get configmap coredns-custom -o yaml
```

```bash
kubectl --context do-sfo3-prod -n kube-system get configmap coredns-custom -o yaml
```

You should see `prom.server`, `loki.server`, and `grafana.server` all pointing to the same `o11y` internal VIP.

4. Check DNS resolution from inside the client clusters.

Run:

```bash
kubectl --context do-sfo3-staging -n default run dns-check-staging --rm -i --restart=Never --image=busybox:1.36 --command -- sh -lc "nslookup prom.vipyrsec.com && nslookup loki.vipyrsec.com && nslookup grafana.vipyrsec.com"
```

```bash
kubectl --context do-sfo3-prod -n default run dns-check-prod --rm -i --restart=Never --image=busybox:1.36 --command -- sh -lc "nslookup prom.vipyrsec.com && nslookup loki.vipyrsec.com && nslookup grafana.vipyrsec.com"
```

If those do not return the current `o11y` internal VIP, the repair did not take.

## What “good” looks like

The repair is complete only when all of these are true:

1. `o11y` ingress Service has an internal VIP.
2. `staging` and `prod` CoreDNS both resolve:
   - `prom.vipyrsec.com`
   - `loki.vipyrsec.com`
   - `grafana.vipyrsec.com`
   to that VIP.
3. Internal HTTPS checks work from both clusters.
4. Prometheus in `o11y` still shows healthy scrape targets.

If even one of those is false, the repair is not complete.

## One sentence summary

If the `o11y` internal LB IP changes, run the script in dry-run mode first, then run it with `--apply`, then do the verification commands until you prove the client clusters resolve and reach the new VIP correctly.
