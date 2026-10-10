#!/usr/bin/env bash
# Harvest dev setup, part 2 (inside Ubuntu on WSL). Run:
#   bash '/mnt/c/path/to/harvest/setup/2-wsl-setup.sh'
set -euo pipefail

say() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }

say "[1/5] System packages (Swift deps, FUSE for the xtool AppImage, libimobiledevice tools)"
sudo apt-get update
sudo apt-get install -y \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
  libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev \
  curl rsync libfuse2t64 libimobiledevice-utils

say "[2/5] Swift 6.4 via swiftly"
if ! command -v swiftly >/dev/null 2>&1; then
  cd /tmp
  curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
  tar zxf "swiftly-$(uname -m).tar.gz"
  ./swiftly init --quiet-shell-followup --assume-yes
fi
# shellcheck disable=SC1091
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r
swiftly install 6.4 --use --assume-yes || swiftly use 6.4
swift --version

say "[3/5] xtool"
mkdir -p "$HOME/.local/bin"
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o "$HOME/.local/bin/xtool"
chmod +x "$HOME/.local/bin/xtool"
grep -q 'USBMUXD_SOCKET_ADDRESS' "$HOME/.bashrc" || cat >> "$HOME/.bashrc" <<'EOF'

# Harvest: talk to the iPhone through Apple Devices' service on Windows (WSL mirrored networking)
export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015
export PATH="$HOME/.local/bin:$PATH"
EOF
export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015
export PATH="$HOME/.local/bin:$PATH"
xtool --help | head -3

say "[4/5] Copying the project into Linux and running the core tests"
rsync -a --delete --exclude .build "/mnt/c/path/to/harvest/" "$HOME/harvest/"
(cd "$HOME/harvest/Packages/HarvesterCore" && swift test)

say "[5/5] iPhone check"
if ideviceinfo -k DeviceName 2>/dev/null; then
  echo "iPhone visible ✔"
else
  echo "iPhone not visible yet. Plug it in, open Apple Devices on Windows, tap Trust on the iPhone, then run: ideviceinfo -k DeviceName"
fi

cat <<'EOF'

Almost there. Two interactive steps left (they need your Apple ID):
  1. xtool setup
       - login mode: 1 (Password) unless you have a paid developer account
       - when it asks for Xcode.xip, give the path, e.g.  /mnt/c/path/to/Downloads/Xcode_27.xip
  2. bash '/mnt/c/path/to/harvest/setup/run.sh'
       - builds Harvest and installs it on the iPhone
       - first time: iPhone Settings → Privacy & Security → Developer Mode → On,
         then Settings → General → VPN & Device Management → trust your Apple ID
EOF
