#!/usr/bin/env bash
# Local build script for the Cygnus ZMK firmware.
#
# This is a "module-style" config (zephyr/module.yml declares board_root: .), the
# same layout CI builds. Like the GitHub Actions workflow, the west workspace is
# created OUTSIDE the repo (in $ZMK_WORKSPACE), while the repo itself is passed
# to the build as the ZMK extra module. Keeping the workspace separate avoids a
# recursion where Zephyr would try to "source" the workspace Zephyr checkout's
# own Kconfig.
#
# Build matrix (mirrors build.yaml):
#   left   -> cygnus_left   (ZMK Studio, studio-rpc-usb-uart)
#   right  -> cygnus_right
#   reset  -> settings_reset
#
# Usage:
#   ./build.sh            # build left and right (reset skipped)
#   ./build.sh --all      # build left, right and reset
#   ./build.sh --left
#   ./build.sh --right
#   ./build.sh --reset
#   ./build.sh --setup    # only init/update/export, no build
#   ./build.sh --clean    # wipe the workspace (like CI's fresh checkout)
#
# Firmware output in $ZMK_WORKSPACE/build/<side>/zephyr/zmk.uf2 (or zmk.bin).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD=nice_nano//zmk
WORKSPACE="${ZMK_WORKSPACE:-$HOME/.cache/zmk-cygnus-ws}"
CONFIG_DIR="$REPO_ROOT/config"
EXTRA_MODULES="$REPO_ROOT"

BLD_LEFT=0
BLD_RIGHT=0
BLD_RESET=0
DO_SETUP=1
DO_CLEAN=0

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

ws_run() {
    (cd "$WORKSPACE" && "$@")
}

# The nanopb generator is a python script invoked via `#!/usr/bin/env python3`
# as a protoc plugin. When west runs, it prepends its own python to PATH ahead
# of the one that has google.protobuf, so protoc-gen-nanopb fails to import it.
# Export PYTHONPATH to the site-packages of whatever python3 actually has the
# google protobuf package, so any python3 west spawns can import it too.
export PYTHONPATH="${PYTHONPATH:-}"
for p in $(python3 -c 'import google.protobuf, os; print(os.path.dirname(os.path.dirname(os.path.dirname(google.protobuf.__file__))))' 2>/dev/null); do
    case ":$PYTHONPATH:" in
        *":$p:"*) ;;
        *) PYTHONPATH="$p${PYTHONPATH:+:$PYTHONPATH}" ;;
    esac
done
export PYTHONPATH

do_clean() {
    if [ -d "$WORKSPACE" ]; then
        echo "[clean] $WORKSPACE"
        rm -rf "$WORKSPACE"
    fi
}

do_setup() {
    echo "[setup] workspace: $WORKSPACE"
    mkdir -p "$WORKSPACE/config"
    # Like CI: fresh copy of the config (manifest + keymap + conf) into the workspace.
    cp -R "$CONFIG_DIR"/. "$WORKSPACE/config/"

    if [ ! -d "$WORKSPACE/.west" ]; then
        echo "[setup] west init -l config"
        (cd "$WORKSPACE" && west init -l config)
    fi
    echo "[setup] west update"
    ws_run west update --fetch-opt=--filter=tree:0
    echo "[setup] west zephyr-export"
    ws_run west zephyr-export
}

build_one() {
    local side="$1"
    local shield="$2"
    shift 2
    echo
    echo ">>> west build -s zmk/app -b $BOARD -d build/$side -- -DSHIELD=$shield"
    ws_run west build -s zmk/app -b "$BOARD" -d "build/$side" -- \
        "-DSHIELD=$shield" \
        "-DZMK_CONFIG=$CONFIG_DIR" \
        "-DZMK_EXTRA_MODULES=$EXTRA_MODULES" \
        "$@"
    echo "<<< done: $WORKSPACE/build/$side/zephyr/zmk.*"
}

if [ $# -eq 0 ]; then
    BLD_LEFT=1
    BLD_RIGHT=1
else
    for arg in "$@"; do
        case "$arg" in
            --all)   BLD_LEFT=1; BLD_RIGHT=1; BLD_RESET=1 ;;
            --left)  BLD_LEFT=1 ;;
            --right) BLD_RIGHT=1 ;;
            --reset) BLD_RESET=1 ;;
            --setup) BLD_LEFT=0; BLD_RIGHT=0; BLD_RESET=0 ;;
            --clean) DO_CLEAN=1 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "unknown argument: $arg"; usage; exit 1 ;;
        esac
    done
fi

[ $DO_CLEAN -eq 1 ] && do_clean
[ $DO_SETUP -eq 1 ] && do_setup

echo
echo "[workspace] repo     $REPO_ROOT"
echo "[workspace] board    $BOARD"
echo "[workspace] config   $CONFIG_DIR"

if [ $BLD_LEFT -eq 1 ]; then
    build_one left cygnus_left -S studio-rpc-usb-uart -DCONFIG_ZMK_STUDIO=y
fi
if [ $BLD_RIGHT -eq 1 ]; then
    build_one right cygnus_right
fi
if [ $BLD_RESET -eq 1 ]; then
    build_one reset settings_reset
fi

echo
echo "All requested builds finished."