#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Logging & errors
###############################################################################
log()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

###############################################################################
# Preconditions
###############################################################################
pve_require_base_cmds() {
  [[ $EUID -eq 0 ]] || die "Run as root on the Proxmox host."
  for c in pct pvesm pveversion awk sed grep ping; do
    require_cmd "$c"
  done
}

###############################################################################
# Community-derived helpers (MIT)
# Source: https://github.com/community-scripts/ProxmoxVE
###############################################################################
maxkeys_check() {
  local maxkeys maxbytes used_keys used_bytes
  maxkeys=$(cat /proc/sys/kernel/keys/maxkeys 2>/dev/null || echo 0)
  maxbytes=$(cat /proc/sys/kernel/keys/maxbytes 2>/dev/null || echo 0)

  [[ "$maxkeys" -gt 0 && "$maxbytes" -gt 0 ]] || die "Unable to read kernel keyring limits"

  used_keys=$(awk '/100000:/ {print $2}' /proc/key-users 2>/dev/null || echo 0)
  used_bytes=$(awk '/100000:/ {split($5,a,"/"); print a[1]}' /proc/key-users 2>/dev/null || echo 0)

  if (( used_keys > maxkeys - 100 || used_bytes > maxbytes - 1000 )); then
    die "Kernel keyring limits nearly exhausted; increase kernel.keys.maxkeys/maxbytes"
  fi
}

###############################################################################
# IP helpers
###############################################################################
ip_to_int() { local IFS=.; read -r a b c d <<<"$1"; echo $(((a<<24)+(b<<16)+(c<<8)+d)); }
int_to_ip() { local x=$1; echo "$(((x>>24)&255)).$(((x>>16)&255)).$(((x>>8)&255)).$((x&255))"; }

is_ip_range() {
  local re='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}-([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
  [[ "${1:-}" =~ $re ]]
}

resolve_ip_from_range() {
  local range="$1"
  local start="${range%%-*}"
  local end="${range##*-}"
  local start_ip="${start%%/*}"
  local end_ip="${end%%/*}"
  local cidr="${start##*/}"

  local s e
  s=$(ip_to_int "$start_ip")
  e=$(ip_to_int "$end_ip")

  local i ip
  for ((i=s; i<=e; i++)); do
    ip="$(int_to_ip "$i")"
    if ! ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
      echo "$ip/$cidr"
      return 0
    fi
  done
  return 1
}

pve_normalize_ip() {
  local ip="$1"
  [[ "$ip" == "dhcp" ]] && { echo "dhcp"; return 0; }
  if is_ip_range "$ip"; then
    resolve_ip_from_range "$ip" || return 1
    return 0
  fi
  echo "$ip"
}

###############################################################################
# Proxmox helpers
###############################################################################
pve_storage_exists() {
  pvesm status | awk '{print $1}' | grep -qx "$1"
}

pve_ct_exists() {
  pct status "$1" >/dev/null 2>&1
}

pve_ct_running() {
  pct status "$1" 2>/dev/null | grep -qi "status: running"
}

pct_exec() {
  local ct="$1"; shift
  pct exec "$ct" -- bash -lc "$*"
}

pve_ct_ensure_started() {
  local ct="$1"
  if ! pve_ct_running "$ct"; then
    log "Starting CT $ct"
    pct start "$ct" || die "Failed to start CT $ct"
    sleep 3
  fi
}

###############################################################################
# CT creation (FIXED: positional params ≥ 10)
###############################################################################
pve_ct_create_privileged() {
  local ct="$1"
  local hostname="$2"
  local storage="$3"
  local disk_gb="$4"
  local mem_mb="$5"
  local swap_mb="$6"
  local cores="$7"
  local bridge="$8"
  local ip_cidr="$9"
  local gateway="${10}"
  local dns="${11}"
  local ostemplate="${12}"

  pve_storage_exists "$storage" || die "Storage '$storage' not found"
  maxkeys_check

  local net0="name=eth0,bridge=${bridge},ip=${ip_cidr}"
  [[ -n "$gateway" && "$ip_cidr" != "dhcp" ]] && net0="${net0},gw=${gateway}"

  log "Creating CT $ct ($hostname) using template $ostemplate"
  pct create "$ct" "$ostemplate" \
    --hostname "$hostname" \
    --storage "$storage" \
    --rootfs "${storage}:${disk_gb}" \
    --memory "$mem_mb" \
    --swap "$swap_mb" \
    --cores "$cores" \
    --net0 "$net0" \
    --unprivileged 0 \
    --features "nesting=1,keyctl=1" \
    --onboot 1 \
    --startup "order=20" \
    || die "pct create failed for CT $ct"
}

###############################################################################
# Common CT setup helpers
###############################################################################
ct_install_base_tools() {
  local ct="$1"
  pct_exec "$ct" "apt-get update -y"
  pct_exec "$ct" "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git jq openssl"
}

ct_install_docker_debian() {
  local ct="$1"
  pct_exec "$ct" "
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  "
}

###############################################################################
# File & compose helpers
###############################################################################
ct_write_file_stdin() {
  local ct="$1"
  local path="$2"
  pct_exec "$ct" "install -d \"$(dirname "$path")\""
  pct exec "$ct" -- bash -lc "cat > \"$path\""
}

ct_stack_up() {
  local ct="$1"
  local dir="$2"
  pct_exec "$ct" "cd \"$dir\" && docker compose pull && docker compose up -d"
}

###############################################################################
# Networking helpers
###############################################################################
pve_ct_get_ipv4() {
  local ct="$1"
  local ip
  ip="$(pct_exec "$ct" "hostname -I | awk '{print \$1}'" 2>/dev/null || true)"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }
  return 1
}
