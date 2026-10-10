#!/usr/bin/env bash
# Sync the project from Windows into Linux, build a release build and install it on the iPhone.
# Also how you re-sign it every 7 days on a free Apple ID.
#   bash '/mnt/c/path/to/harvest/setup/run.sh'
set -euo pipefail

export USBMUXD_SOCKET_ADDRESS="${USBMUXD_SOCKET_ADDRESS:-127.0.0.1:27015}"
export PATH="$HOME/.local/bin:$PATH"
# shellcheck disable=SC1091
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"

rsync -a --delete --exclude .build "/mnt/c/path/to/harvest/" "$HOME/harvest/"
cd "$HOME/harvest"
xtool dev -c release "$@"
