#!/usr/bin/env bash
#
# validate.sh — print warnings (⚠) and passed checks (✓) for the parsed infra.
# Heuristic, source-text based — meant to teach, not to be exhaustive.
#

ip_warn()  { printf '  %s⚠%s  %s\n' "${YEL:-}" "${RST:-}" "$1"; }
ip_ok()    { printf '  %s✓%s  %s\n' "${GRN:-}" "${RST:-}" "$1"; }

# does the parsed model contain a resource whose type matches a glob?
ip_has_type() {
  local pat="$1" id t
  for id in "${IP_RES_ID[@]}"; do
    t=$(printf '%s' "${IP_RES_TYPE[$id]}" | tr '[:upper:]' '[:lower:]')
    case "$t" in $pat) return 0 ;; esac
  done
  return 1
}

ip_validate() {
  case "$IP_FORMAT" in
    terraform|cdk) ip_validate_aws ;;
    compose)       ip_validate_compose ;;
    k8s)           ip_validate_k8s ;;
  esac
}

# ---------------------------------------------------------------------------
ip_validate_aws() {
  local raw="$IP_RAW"
  local any=0

  if printf '%s' "$raw" | grep -qE '0\.0\.0\.0/0'; then
    if printf '%s' "$raw" | grep -qE '(from_port|FromPort)[^0-9]*22\b|port[^0-9]*22\b'; then
      ip_warn "Security group allows 0.0.0.0/0 on port 22 (SSH open to the world)"; any=1
    else
      ip_warn "A security group / rule allows 0.0.0.0/0 — confirm this is intentional"; any=1
    fi
  fi

  if ip_has_type '*s3*' || ip_has_type '*bucket*'; then
    if printf '%s' "$raw" | grep -qiE 'public-read|"PublicRead"|AllUsers'; then
      ip_warn "Public S3 bucket detected — is this intentional?"; any=1
    fi
    if ! printf '%s' "$raw" | grep -qi 'versioning'; then
      ip_warn "S3 bucket has no versioning enabled"; any=1
    fi
  fi

  if ip_has_type '*lambda*' || ip_has_type '*function*'; then
    if ! printf '%s' "$raw" | grep -qiE 'timeout'; then
      ip_warn "Lambda timeout not set (default 3s may be too low)"; any=1
    fi
    if printf '%s' "$raw" | grep -qiE 'iam_role|RoleName|"Role"|role[ \t]*='; then
      ip_ok "All Lambda functions appear to have an IAM role"
    fi
  fi

  if printf '%s' "$raw" | grep -qiE 'private[_-]?subnet|map_public_ip_on_launch[ \t]*=[ \t]*false'; then
    ip_ok "Resources reference a private subnet"
  fi

  if ip_has_type '*db*' || ip_has_type '*rds*' || ip_has_type '*dynamodb*'; then
    if printf '%s' "$raw" | grep -qiE 'encryption|kms_key|server_side_encrypt|storageencrypted|sse_algorithm'; then
      ip_ok "Data store has encryption configured"
    else
      ip_warn "Data store has no encryption-at-rest configured"; any=1
    fi
  fi

  [ "$any" -eq 0 ] && ip_ok "No obvious misconfigurations found"
}

# ---------------------------------------------------------------------------
ip_validate_compose() {
  local raw="$IP_RAW"
  local any=0

  if printf '%s' "$raw" | grep -qiE 'privileged:[ \t]*true'; then
    ip_warn "A service runs in privileged mode — grants host-level access"; any=1
  fi
  if printf '%s' "$raw" | grep -qE '\b0\.0\.0\.0:'; then
    ip_warn "A service binds to 0.0.0.0 — exposed on all interfaces"; any=1
  fi
  if printf '%s' "$raw" | grep -qiE '(password|secret|token)[^:]*[:=][ \t]*[^$\n]'; then
    ip_warn "Possible hard-coded secret in environment — use a .env file or secrets"; any=1
  fi
  if printf '%s' "$raw" | grep -qiE ':latest'; then
    ip_warn "Image pinned to ':latest' — builds are not reproducible"; any=1
  fi

  # services that publish ports without depends_on are fine; note exposed ones
  local id
  for id in "${IP_RES_ID[@]}"; do
    case "${IP_RES_META[$id]}" in
      *ingress=1*) ip_ok "Service '${IP_RES_NAME[$id]}' publishes ports (entry point)" ;;
    esac
  done

  if printf '%s' "$raw" | grep -qiE 'restart:'; then
    ip_ok "Services define a restart policy"
  fi

  [ "$any" -eq 0 ] && ip_ok "No obvious misconfigurations found"
}

# ---------------------------------------------------------------------------
ip_validate_k8s() {
  local raw="$IP_RAW"
  local any=0

  if printf '%s' "$raw" | grep -qiE 'privileged:[ \t]*true'; then
    ip_warn "A container requests privileged: true"; any=1
  fi
  if printf '%s' "$raw" | grep -qiE 'hostNetwork:[ \t]*true'; then
    ip_warn "A pod uses hostNetwork: true"; any=1
  fi
  if ! printf '%s' "$raw" | grep -qiE 'resources:'; then
    ip_warn "No resource requests/limits found — pods can starve the node"; any=1
  else
    ip_ok "Workloads define resource requests/limits"
  fi
  if ! printf '%s' "$raw" | grep -qiE 'livenessProbe|readinessProbe'; then
    ip_warn "No liveness/readiness probes found"; any=1
  else
    ip_ok "Workloads define health probes"
  fi
  if printf '%s' "$raw" | grep -qiE 'type:[ \t]*LoadBalancer'; then
    ip_ok "A Service of type LoadBalancer is the public entry point"
  fi

  [ "$any" -eq 0 ] && ip_ok "No obvious misconfigurations found"
}
