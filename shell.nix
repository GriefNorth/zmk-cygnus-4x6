# Development shell for locally building the Cygnus ZMK firmware.
#
# Provides the full ZMK toolchain: Python/west environment, CMake, Ninja,
# device-tree compiler, gperf, ccache, flashing tools, and the Zephyr SDK.
#
# ZMK (app/west.yml) is pinned to Zephyr v4.1.0+zmk-fixes, which requires the
# Zephyr SDK 0.16.x. That SDK is a large (non-Nix) binary distribution, so it is
# downloaded once on first entry of this shell and cached in ~/.cache/zmk-sdk.
#
# One-time setup inside the shell:
#
#     west init -l config
#     west update
#     west zephyr-export
#
# Build the left (studio) / right halves:
#
#     west build -s zmk/app -b nice_nano//zmk -S studio-rpc-usb-uart \
#       -- -DSHIELD=cygnus_left -DZMK_CONFIG="$(pwd)/config" \
#          -DZMK_EXTRA_MODULES="$(pwd)" -DCONFIG_ZMK_STUDIO=y
#     west build -s zmk/app -b nice_nano//zmk -d build_right \
#       -- -DSHIELD=cygnus_right -DZMK_CONFIG="$(pwd)/config" \
#          -DZMK_EXTRA_MODULES="$(pwd)"
#
# The built firmware lands in build*/zephyr/zmk.uf2 (or zmk.bin).

{ pkgs ? import <nixpkgs> {} }:

let
  zephyrVersion = "v4.1.0+zmk-fixes";
  sdkVersion = "0.16.9";
  sdkUrl = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${sdkVersion}/zephyr-sdk-${sdkVersion}_linux-x86_64.tar.xz";

  # Python environment with all packages listed in Zephyr's requirements-base.txt.
  pythonEnv = pkgs.python3.withPackages (python-pkgs: with python-pkgs; [
    west                # Zephyr's meta-tool (pulls in west-core etc.)
    pyelftools
    pyyaml
    pykwalify
    jsonschema
    canopen
    packaging
    patool
    psutil
    pyserial
    requests
    semver
    tqdm
    intelhex
    anytree
    pip
    wheel
    setuptools
  ]);
in
pkgs.mkShell {
  name = "zmk-cygnus-builder";
  nativeBuildInputs = with pkgs; [
    pythonEnv
    cmake
    ninja
    dtc                  # device-tree compiler used by Zephyr's dts build step
    gperf                # BLE controller code generation
    ccache
    git
    curl
    xz
    gcc
    dfu-util             # flasher for nice_nano (nRF5x)
  ];

  # The Zephyr SDK tarball contains the "arm-zephyr-eabi" toolchain that ZMK
  # actually links the firmware with. It cannot be fetched at evaluation time
  # (large, versioned, not packaged in nixpkgs), so the shellHook downloads and
  # extracts it once into a user cache.
  shellHook = ''
    set -euo pipefail
    export LC_ALL=C

    # ---------------------- Zephyr SDK ----------------------
    if [ -z "''${ZEPHYR_SDK_INSTALL_DIR:-}" ]; then
      sdk_dir="$HOME/.cache/zmk-sdk/zephyr-sdk-${sdkVersion}"
      if [ ! -x "$sdk_dir/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" ]; then
        echo "Downloading Zephyr SDK ${sdkVersion} (~150MB) ..."
        mkdir -p "$HOME/.cache/zmk-sdk"
        tmp_tar="$(mktemp --suffix=.tar.xz)"
        curl -fsSL "${sdkUrl}" -o "$tmp_tar"
        mkdir -p "$sdk_dir"
        tar -xJf "$tmp_tar" -C "$sdk_dir" --strip-components=1
        rm -f "$tmp_tar"
      fi
      export ZEPHYR_SDK_INSTALL_DIR="$sdk_dir"
    fi
    export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

    echo "Zephyr SDK : $ZEPHYR_SDK_INSTALL_DIR"
    echo "west       : $(west --version)"
    echo
    echo "Next steps:"
    echo "  west init -l config && west update && west zephyr-export"
    echo "  west build -s zmk/app ... (see top of shell.nix)"
  '';
}