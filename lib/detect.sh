#!/usr/bin/env bash
#
# detect.sh — auto-detection of infrastructure type for a directory.
# Sourceable independently: defines ip_detect and ip_detect_localstack.
#

# ip_detect DIR  -> echoes one of: terraform | compose | cdk | k8s  (empty if none)
ip_detect() {
  local dir="${1:-.}"
  local f

  # Terraform: any *.tf file
  for f in "$dir"/*.tf; do
    [ -e "$f" ] && { echo "terraform"; return 0; }
  done

  # Docker Compose
  for f in "$dir/docker-compose.yml" "$dir/docker-compose.yaml" \
           "$dir/compose.yml" "$dir/compose.yaml"; do
    [ -f "$f" ] && { echo "compose"; return 0; }
  done

  # AWS CDK: cdk.json present
  if [ -f "$dir/cdk.json" ]; then
    echo "cdk"; return 0
  fi

  # Kubernetes: a YAML file that has both apiVersion and kind
  for f in "$dir"/*.yaml "$dir"/*.yml; do
    [ -e "$f" ] || continue
    if grep -qiE '^[[:space:]]*kind:[[:space:]]' "$f" 2>/dev/null \
       && grep -qiE '^[[:space:]]*apiVersion:[[:space:]]' "$f" 2>/dev/null; then
      echo "k8s"; return 0
    fi
  done

  return 1
}

# ip_detect_localstack DIR  -> returns 0 if the project targets LocalStack
ip_detect_localstack() {
  local dir="${1:-.}"
  # Look for the classic LocalStack endpoint (port 4566), the image, or the
  # AWS_ENDPOINT_URL override across common project files.
  if grep -rqiE 'localstack|:4566|endpoint[s]?[^a-z].*4566|AWS_ENDPOINT_URL' \
        "$dir"/*.tf "$dir"/*.yml "$dir"/*.yaml "$dir"/.env "$dir"/cdk.json \
        "$dir"/*.json 2>/dev/null; then
    return 0
  fi
  return 1
}
