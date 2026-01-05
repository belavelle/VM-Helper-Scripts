#!/usr/bin/env bash

set -Eeuo pipefail

#######################################
# Color & logging helpers
#######################################
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

#######################################
# Error trap
#######################################
trap 'log_error "Command failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR

#######################################
# Privilege check
#######################################
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root (use sudo)"
  exit 1
fi

#######################################
# Helper functions
#######################################
stop_service() {
  local svc="$1"
  if systemctl list-units --type=service | grep -q "^${svc}"; then
    log_info "Stopping service: ${svc}"
    systemctl stop "$svc" || log_warn "Failed to stop ${svc}"
  else
    log_warn "Service ${svc} not found"
  fi
}

purge_packages() {
  local pkgs=("$@")
  local installed=()

  for pkg in "${pkgs[@]}"; do
    if dpkg -l | grep -q "^ii  ${pkg}"; then
      installed+=("$pkg")
    fi
  done

  if [[ ${#installed[@]} -gt 0 ]]; then
    log_info "Purging Docker packages: ${installed[*]}"
    apt-get purge -y "${installed[@]}"
  else
    log_warn "No Docker packages found to purge"
  fi
}

remove_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    log_info "Removing directory: $dir"
    rm -rf "$dir"
  else
    log_warn "Directory not found: $dir"
  fi
}

remove_file() {
  local file="$1"
  if [[ -e "$file" ]]; then
    log_info "Removing file: $file"
    rm -f "$file"
  else
    log_warn "File not found: $file"
  fi
}

#######################################
# Execution
#######################################
log_info "Starting complete Docker removal"

log_info "Stopping Docker-related services"
stop_service docker.service
stop_service docker.socket
stop_service containerd.service

log_info "Removing Docker packages"
purge_packages \
  docker \
  docker-engine \
  docker.io \
  docker-ce \
  docker-ce-cli \
  docker-buildx-plugin \
  docker-compose-plugin \
  docker-compose \
  containerd \
  containerd.io \
  runc

log_info "Cleaning up APT dependencies"
apt-get autoremove -y
apt-get autoclean -y

log_info "Removing Docker data and configuration"
remove_dir /var/lib/docker
remove_dir /var/lib/containerd
remove_dir /etc/docker
remove_dir /run/docker
remove_dir /run/containerd

log_info "Removing Docker group"
if getent group docker >/dev/null; then
  groupdel docker || log_warn "Failed to remove docker group"
else
  log_warn "Docker group does not exist"
fi

log_info "Removing leftover binaries"
remove_file /usr/bin/docker
remove_file /usr/bin/dockerd
remove_file /usr/bin/containerd
remove_file /usr/bin/containerd-shim
remove_file /usr/bin/containerd-shim-runc-v2
remove_file /usr/bin/docker-compose

log_info "Removing Docker APT repository"
remove_file /etc/apt/sources.list.d/docker.list
remove_file /etc/apt/keyrings/docker.gpg
remove_file /usr/share/keyrings/docker-archive-keyring.gpg

log_info "Updating APT package index"
apt-get update

log_info "Docker removal completed successfully"
log_info "A system reboot is recommended"