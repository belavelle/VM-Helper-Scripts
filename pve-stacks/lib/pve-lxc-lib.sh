#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "[INFO] $*"; }
die() { echo "[ERR] $*" >&2; exit 1; }

pve_require_base_cmds() {
  [[ $EUID -eq 0 ]] || die "Run as root"
}

pct_exec() { pct exec "$1" -- bash -lc "$2"; }

pve_ct_exists() { pct status "$1" >/dev/null 2>&1; }
pve_ct_running() { pct status "$1" | grep -qi running; }

pve_ct_ensure_started() {
  pve_ct_running "$1" || pct start "$1"
}

pve_normalize_ip() { echo "$1"; }

pve_ct_create_privileged() {
  pct create "$1" "${12}" --hostname "$2" --storage "$3" --rootfs "$3:$4" \
    --memory "$5" --swap "$6" --cores "$7" \
    --net0 "name=eth0,bridge=$8,ip=$9" \
    --unprivileged 0 --features nesting=1,keyctl=1
}

ct_install_base_tools() { pct_exec "$1" "apt-get update -y"; }
ct_install_docker_debian() { pct_exec "$1" "apt-get install -y docker.io docker-compose-plugin"; }

ct_stack_up() { pct_exec "$1" "cd $2 && docker compose up -d"; }

ct_write_file_stdin() {
  pct_exec "$1" "cat > $2"
}

pve_ct_get_ipv4() {
  pct_exec "$1" "hostname -I | awk '{print \$1}'"
}
