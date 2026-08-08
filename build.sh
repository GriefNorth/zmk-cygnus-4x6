#!/usr/bin/env bash
# Local build script for the Cygnus ZMK firmware.
#
# Mirrors the GitHub Actions matrix in build.yaml:
#   left   -> cygnus_left   (ZMK Studio, studio-rpc-usb-uart)
#   right  -> cygnus_right
#   reset  -> settings_reset
#
# Before the first build the script sets up the west workspace once:
#   west init -l config && west update && west zephyr-export
#
# Usage:
#   ./build.sh            # build left and right (reset skipped)
#   ./build.sh --all      # build left, right and reset
#   ./build.sh --left
#   ./build.sh --right
#   ./build.sh --reset
#   ./build.sh --setup    # only init/update/export, no build
#
# Firmware output in build/<side>/zephyr/zmk.uf2 (or zmk.bin).

set -euo pipefail

BOARD=nice_nano//zmk
CONFIG_DIR="$(pwd)/config"
EXTRA_MODULES="$(pwd)"

BLD_LEFT=0
BLD_RIGHT=0
BLD_RESET=0

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
}

do_setup() {
    if [ ! -d .west ]; then
        echo "[setup] west init -l config"
        west init -l config
    fi
    echo "[setup] west update"
    west update --fetch-opt=--filter=tree:0
    echo "[setup] west zephyr-export"
    west zephyr-export
}

build_one() {
    local side="$1"
    shift
    echo
    echo ">>> west build -s zmk/app -b $BOARD -d build/$side -- -DSHIELD=cygnus_$side"
    west build -s zmk/app -b "$BOARD" -d "build/$side" -- \
        "-DSHIELD=cygnus_$side" \
        "-DZMK_CONFIG=$CONFIG_DIR" \
        "-DZMK_EXTRA_MODULES=$EXTRA_MODULES" \
        "$@"
    echo "<<< done: build/$side/zephyr/zmk.*"
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
            -h|--help) usage; exit 0 ;;
            *) echo "unknown argument: $arg"; usage; exit 1 ;;
        esac
    done
fi

do_setup

echo "[workspace] root    $(pwd)"
echo "[workspace] board   $BOARD"
echo "[workspace] config  $CONFIG_DIR"

if [ $BLD_LEFT -eq 1 ]; then
    build_one left -S studio-rpc-usb-uart -DCONFIG_ZMK_STUDIO=y
fi
if [ $BLD_RIGHT -eq 1 ]; then
    build_one right
fi
if [ $BLD_RESET -eq 1 ]; then
    build_one reset
fi

echo
echo "All requested builds finished."