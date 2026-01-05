#!/usr/bin/env bash
# install_xmrig.sh
# Builds xmrig from source and creates a helper launch script.

set -Eeuo pipefail
IFS=$'\n\t'

#######################################
# User-configurable variables (edit these)
#######################################
REPO_URL="https://github.com/xmrig/xmrig.git"
WORKDIR="${WORKDIR:-$HOME}"              # Where to clone/build
XMRIG_DIRNAME="xmrig"                    # Folder name after clone
BUILD_DIRNAME="build"

# Output launch script
MINER_SCRIPT_NAME="mine_cro.sh"
MINER_SCRIPT_MODE="0755"

# Miner command config
ALGO="rx"
POOL_HOST="rx.unmineable.com"
POOL_PORT="443"
POOL_TLS="true"                          # true / false
KEEPALIVE="true"                         # true / false

# Wallet config
COIN_PREFIX="CRO"
WALLET_ADDRESS="0x605E2A4d3fEB3dC8a254961Bf9795aE5d68141D3"
PASSWORD="x"

#######################################
# Hostname detection + sanitization
#######################################
RAW_HOSTNAME="$(hostname -s 2>/dev/null || hostname)"

SANITIZED_HOSTNAME="$(
  echo "$RAW_HOSTNAME" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-' \
    | sed 's/[^a-z0-9_-]//g'
)"

if [[ -z "$SANITIZED_HOSTNAME" ]]; then
  SANITIZED_HOSTNAME="unknown-host"
fi

# Derived value (do not edit)
WALLET="${COIN_PREFIX}:${WALLET_ADDRESS}.${SANITIZED_HOSTNAME}"

#######################################
# Logging helpers
#######################################
ts() { date +"%Y-%m-%d %H:%M:%S"; }
info() { echo -e "$(ts) [INFO]  $*"; }
warn() { echo -e "$(ts) [WARN]  $*" >&2; }
error(){ echo -e "$(ts) [ERROR] $*" >&2; }

die() {
  error "$*"
  exit 1
}

on_err() {
  local exit_code=$?
  local line_no=${1:-"?"}
  error "Script failed at line ${line_no} (exit code: ${exit_code})."
  exit "$exit_code"
}
trap 'on_err $LINENO' ERR

#######################################
# Utility functions
#######################################
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

as_bool_flag() {
  local val="$1"
  local flag="$2"
  if [[ "${val,,}" == "true" ]]; then
    echo "$flag"
  else
    echo ""
  fi
}

apt_install() {
  local pkgs=("$@")
  info "Installing packages: ${pkgs[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

#######################################
# Preconditions
#######################################
need_cmd sudo
need_cmd git

if ! command -v apt-get >/dev/null 2>&1; then
  die "This script currently supports Debian/Ubuntu systems only (apt-get not found)."
fi

#######################################
# Main
#######################################
info "Updating package lists..."
sudo apt-get update -y

info "Upgrading installed packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

DEPS=(
  git automake autoconf pkg-config
  libcurl4-openssl-dev libjansson-dev
  libssl-dev libgmp-dev make g++
  zlib1g-dev libtool
  build-essential cmake libuv1-dev libhwloc-dev
)

apt_install "${DEPS[@]}"

info "Switching to work directory: ${WORKDIR}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ -d "$XMRIG_DIRNAME/.git" ]]; then
  warn "Existing xmrig repo found — pulling latest changes..."
  cd "$XMRIG_DIRNAME"
  git pull --ff-only
else
  if [[ -e "$XMRIG_DIRNAME" ]]; then
    die "Path '$WORKDIR/$XMRIG_DIRNAME' exists but is not a git repo."
  fi
  info "Cloning xmrig repository..."
  git clone "$REPO_URL" "$XMRIG_DIRNAME"
  cd "$XMRIG_DIRNAME"
fi

info "Preparing build directory..."
mkdir -p "$BUILD_DIRNAME"
cd "$BUILD_DIRNAME"

need_cmd cmake
need_cmd make
need_cmd g++

info "Configuring build with cmake..."
cmake ..

JOBS=1
if command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
fi

info "Building xmrig (jobs=${JOBS})..."
make -j "$JOBS"

#######################################
# Create miner launch script
#######################################
MINER_SCRIPT_PATH="$(pwd)/${MINER_SCRIPT_NAME}"

TLS_FLAG="$(as_bool_flag "$POOL_TLS" "--tls")"
KEEPALIVE_FLAG="$(as_bool_flag "$KEEPALIVE" "-k")"
POOL="${POOL_HOST}:${POOL_PORT}"

info "Creating miner launch script: ${MINER_SCRIPT_PATH}"
cat > "$MINER_SCRIPT_PATH" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

XMRIG_BIN="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/xmrig"

if [[ ! -x "\$XMRIG_BIN" ]]; then
  echo "[ERROR] xmrig binary not found or not executable at: \$XMRIG_BIN" >&2
  exit 1
fi

exec "\$XMRIG_BIN" \\
  -a "$ALGO" \\
  -o "$POOL" \\
  $TLS_FLAG \\
  $KEEPALIVE_FLAG \\
  -u "$WALLET" \\
  -p "$PASSWORD"
EOF

chmod "$MINER_SCRIPT_MODE" "$MINER_SCRIPT_PATH"

#######################################
# Summary
#######################################
info "Build completed successfully."
info "Sanitized hostname : $SANITIZED_HOSTNAME"
info "Wallet string      : $WALLET"
info "Build directory    : $(pwd)"
info "Miner script       : $MINER_SCRIPT_PATH"
