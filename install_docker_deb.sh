#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------
# Docker + Docker Desktop installer for Ubuntu
# ----------------------------

LOG_FILE="/var/log/docker-install.log"
DESKTOP_DEB_TMP="/tmp/docker-desktop.deb"

# Pretty printing
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*" | tee -a "$LOG_FILE"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" | tee -a "$LOG_FILE" >&2; }

die() {
  error "$*"
  exit 1
}

cleanup() {
  if [[ -f "$DESKTOP_DEB_TMP" ]]; then
    rm -f "$DESKTOP_DEB_TMP" || true
  fi
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run this script as root (e.g., sudo $0)"
  fi
}

ubuntu_check() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS (missing /etc/os-release)."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This script is intended for Ubuntu. Detected ID='${ID:-unknown}'."
  fi

  if [[ -z "${VERSION_CODENAME:-}" ]]; then
    die "Cannot detect Ubuntu codename (VERSION_CODENAME is empty)."
  fi

  info "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME})."
}

apt_update() {
  info "Updating apt package index..."
  apt-get update -y >>"$LOG_FILE" 2>&1 || die "apt-get update failed."
}

install_prereqs() {
  info "Installing prerequisites..."
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    uidmap \
    >>"$LOG_FILE" 2>&1 || die "Failed to install prerequisites."
}

setup_docker_repo() {
  info "Setting up Docker official apt repo..."
  install -m 0755 -d /etc/apt/keyrings >>"$LOG_FILE" 2>&1 || die "Failed to create /etc/apt/keyrings."

  # GPG key
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
      >>"$LOG_FILE" 2>&1 || die "Failed to install Docker GPG key."
    chmod a+r /etc/apt/keyrings/docker.gpg >>"$LOG_FILE" 2>&1 || die "Failed to chmod docker.gpg."
  else
    info "Docker GPG key already present."
  fi

  # Repo entry
  # shellcheck disable=SC1091
  . /etc/os-release
  local arch
  arch="$(dpkg --print-architecture)"
  local repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]] || ! grep -q "download.docker.com/linux/ubuntu" /etc/apt/sources.list.d/docker.list; then
    echo "$repo_line" >/etc/apt/sources.list.d/docker.list
    info "Added Docker repo: $repo_line"
  else
    info "Docker repo already configured."
  fi
}

install_docker_engine() {
  apt_update
  info "Installing Docker Engine and plugins..."
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    >>"$LOG_FILE" 2>&1 || die "Failed to install Docker Engine packages."

  info "Enabling and starting Docker..."
  systemctl enable --now docker >>"$LOG_FILE" 2>&1 || die "Failed to enable/start docker service."
}

configure_docker_group() {
  local target_user="${SUDO_USER:-}"
  if [[ -z "$target_user" ]]; then
    warn "SUDO_USER not set; skipping docker group user add."
    return 0
  fi

  info "Adding user '$target_user' to docker group..."
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker >>"$LOG_FILE" 2>&1 || die "Failed to create docker group."
  fi

  usermod -aG docker "$target_user" >>"$LOG_FILE" 2>&1 || die "Failed to add user to docker group."

  info "User '$target_user' added to docker group (you must log out/in for it to take effect)."
}

install_desktop_prereqs() {
  info "Installing Docker Desktop prerequisites..."
  apt-get install -y \
    gnome-terminal \
    pass \
    >>"$LOG_FILE" 2>&1 || true

  # Desktop needs virt features for best experience; don't hard-fail if not available.
  apt-get install -y \
    qemu-kvm \
    >>"$LOG_FILE" 2>&1 || warn "Could not install qemu-kvm (continuing)."
}

download_desktop_deb_latest_guess() {
  # Docker doesn't provide a stable "latest" URL that always works across time.
  # We'll attempt to find the most recent .deb via a lightweight method:
  # 1) Try a known "stable" path pattern (may fail)
  # 2) If it fails, fall back to installing Docker Desktop via Docker's apt repo (if available)

  info "Attempting to download Docker Desktop .deb..."
  # Commonly used endpoint (may change). If it fails, we'll fall back.
  local url="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"

  if curl -fL --retry 3 --retry-delay 2 -o "$DESKTOP_DEB_TMP" "$url" >>"$LOG_FILE" 2>&1; then
    info "Downloaded Docker Desktop package to $DESKTOP_DEB_TMP"
    return 0
  fi

  warn "Direct download failed from $url"
  return 1
}

install_desktop_from_deb() {
  info "Installing Docker Desktop from .deb..."
  # dpkg may fail due to missing deps; fix with apt-get -f install
  if ! dpkg -i "$DESKTOP_DEB_TMP" >>"$LOG_FILE" 2>&1; then
    warn "dpkg reported missing dependencies; attempting to fix..."
    apt-get install -f -y >>"$LOG_FILE" 2>&1 || die "Failed to fix dependencies for Docker Desktop."
  fi
}

install_desktop_from_apt_repo_if_available() {
  # Some environments may provide docker-desktop via Docker repo.
  # We'll try it as a fallback.
  info "Trying to install docker-desktop via apt (fallback)..."
  apt_update
  if apt-cache show docker-desktop >/dev/null 2>&1; then
    apt-get install -y docker-desktop >>"$LOG_FILE" 2>&1 || die "Failed to install docker-desktop via apt."
    return 0
  fi
  return 1
}

post_install_checks() {
  info "Running post-install checks..."

  require_cmd docker

  docker --version | tee -a "$LOG_FILE"
  docker compose version | tee -a "$LOG_FILE" || warn "docker compose plugin not responding."
  systemctl is-active --quiet docker && info "Docker service is active." || die "Docker service is not active."

  # Non-root test message only (cannot reliably run as target user within this script)
  info "If you added your user to the docker group, log out/in then run: docker run --rm hello-world"

  # Desktop service check if installed
  if systemctl list-unit-files | grep -q '^docker-desktop\.service'; then
    info "Docker Desktop service is present. You can start it with: systemctl --user start docker-desktop"
    info "Or launch it from your app menu: Docker Desktop"
  else
    warn "Docker Desktop systemd unit not detected (it may still be installed as a desktop app)."
  fi
}

main() {
  require_root
  touch "$LOG_FILE" || die "Cannot write log file at $LOG_FILE"
  chmod 0644 "$LOG_FILE" || true

  ubuntu_check
  install_prereqs
  setup_docker_repo
  install_docker_engine
  configure_docker_group
  install_desktop_prereqs

  if download_desktop_deb_latest_guess; then
    install_desktop_from_deb
  else
    if ! install_desktop_from_apt_repo_if_available; then
      warn "Could not install Docker Desktop automatically."
      warn "You can manually download it from Docker Desktop for Linux and install the .deb."
      warn "Docker Engine is installed and working."
    fi
  fi

  post_install_checks

  info "Done. Log: $LOG_FILE"
}

main "$@"
