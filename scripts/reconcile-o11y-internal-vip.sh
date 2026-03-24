#!/usr/bin/env bash

set -euo pipefail

readonly O11Y_CONTEXT="do-sfo3-o11y"
readonly STAGING_CONTEXT="do-sfo3-staging"
readonly PROD_CONTEXT="do-sfo3-prod"
readonly O11Y_NAMESPACE="default"
readonly O11Y_SERVICE="vipyrsec-ingress-nginx-controller"
readonly COREDNS_NAMESPACE="kube-system"
readonly COREDNS_CONFIGMAP="coredns-custom"
readonly COREDNS_DEPLOYMENT="coredns"

usage() {
  cat <<'EOF'
Usage:
  reconcile-o11y-internal-vip.sh [--apply]

What it does:
  1. Reads the current internal o11y load balancer VIP from:
     context do-sfo3-o11y, namespace default, service vipyrsec-ingress-nginx-controller
  2. Compares that VIP to the live coredns-custom ConfigMap in:
     - do-sfo3-staging
     - do-sfo3-prod
  3. If --apply is provided, updates prom.vipyrsec.com, loki.vipyrsec.com, and
     grafana.vipyrsec.com to the current VIP and restarts CoreDNS in both clusters.

Default mode:
  Dry-run only. Nothing is changed unless you pass --apply.

Requirements:
  - kubectl installed
  - kube contexts available for do-sfo3-o11y, do-sfo3-staging, do-sfo3-prod
  - permission to update ConfigMaps and restart CoreDNS in staging and prod
EOF
}

log() {
  printf '[reconcile-o11y-internal-vip] %s\n' "$*"
}

die() {
  printf '[reconcile-o11y-internal-vip] ERROR: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

get_o11y_vip() {
  kubectl --context "$O11Y_CONTEXT" -n "$O11Y_NAMESPACE" \
    get svc "$O11Y_SERVICE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

render_coredns_configmap() {
  local vip="$1"
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${COREDNS_CONFIGMAP}
  namespace: ${COREDNS_NAMESPACE}
data:
  prom.server: |
    prom.vipyrsec.com:53 {
      hosts {
        ${vip} prom.vipyrsec.com
        fallthrough
      }
    }
  loki.server: |
    loki.vipyrsec.com:53 {
      hosts {
        ${vip} loki.vipyrsec.com
        fallthrough
      }
    }
  grafana.server: |
    grafana.vipyrsec.com:53 {
      hosts {
        ${vip} grafana.vipyrsec.com
        fallthrough
      }
    }
EOF
}

get_cluster_vips() {
  local context="$1"
  kubectl --context "$context" -n "$COREDNS_NAMESPACE" \
    get configmap "$COREDNS_CONFIGMAP" \
    -o jsonpath='{.data.prom\.server}{"\n"}{.data.loki\.server}{"\n"}{.data.grafana\.server}{"\n"}'
}

show_cluster_status() {
  local context="$1"
  local vip="$2"
  local live_data

  live_data="$(get_cluster_vips "$context" || true)"

  printf '\nContext: %s\n' "$context"
  printf 'Expected VIP: %s\n' "$vip"
  printf 'Live coredns-custom data:\n%s\n' "${live_data:-<empty>}"
}

apply_cluster() {
  local context="$1"
  local vip="$2"

  log "Applying updated coredns-custom to ${context}"
  render_coredns_configmap "$vip" | kubectl --context "$context" apply -f -

  log "Restarting CoreDNS in ${context}"
  kubectl --context "$context" -n "$COREDNS_NAMESPACE" rollout restart deployment "$COREDNS_DEPLOYMENT"

  log "Waiting for CoreDNS rollout in ${context}"
  kubectl --context "$context" -n "$COREDNS_NAMESPACE" rollout status deployment "$COREDNS_DEPLOYMENT" --timeout=180s
}

verify_resolution() {
  local context="$1"
  local host="$2"
  local expected_vip="$3"
  local output

  output="$(
    kubectl --context "$context" -n default run "dns-check-${host//./-}" \
      --rm -i --restart=Never --image=busybox:1.36 \
      --command -- sh -lc "nslookup ${host}" 2>/dev/null || true
  )"

  printf '\nResolution check for %s in %s:\n%s\n' "$host" "$context" "$output"
  printf '%s' "$output" | rg -q "$expected_vip" || die "${context} does not resolve ${host} to ${expected_vip}"
}

main() {
  local apply_mode="false"

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--apply" ]]; then
    apply_mode="true"
  elif [[ $# -gt 0 ]]; then
    usage
    die "unknown argument: $1"
  fi

  require_tool kubectl
  require_tool rg

  local vip
  vip="$(get_o11y_vip)"
  [[ -n "$vip" ]] || die "o11y internal load balancer VIP is empty"

  log "Detected o11y internal VIP: ${vip}"

  show_cluster_status "$STAGING_CONTEXT" "$vip"
  show_cluster_status "$PROD_CONTEXT" "$vip"

  if [[ "$apply_mode" != "true" ]]; then
    log "Dry-run only. Re-run with --apply to update staging and prod."
    exit 0
  fi

  apply_cluster "$STAGING_CONTEXT" "$vip"
  apply_cluster "$PROD_CONTEXT" "$vip"

  verify_resolution "$STAGING_CONTEXT" "prom.vipyrsec.com" "$vip"
  verify_resolution "$STAGING_CONTEXT" "loki.vipyrsec.com" "$vip"
  verify_resolution "$STAGING_CONTEXT" "grafana.vipyrsec.com" "$vip"
  verify_resolution "$PROD_CONTEXT" "prom.vipyrsec.com" "$vip"
  verify_resolution "$PROD_CONTEXT" "loki.vipyrsec.com" "$vip"
  verify_resolution "$PROD_CONTEXT" "grafana.vipyrsec.com" "$vip"

  log "Reconciliation complete."
}

main "$@"
