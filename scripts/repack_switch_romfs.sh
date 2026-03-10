#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build_switch}"
APP_NAME="Lorealis"
AUTHOR="ns-chat"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR_PATH="$REPO_ROOT/$BUILD_DIR"
ELF_PATH="$BUILD_DIR_PATH/Lorealis.elf"
NRO_PATH="$BUILD_DIR_PATH/Lorealis.nro"
ICON_PATH="$REPO_ROOT/res/img/demo_icon.jpg"
STAGE_DIR="$BUILD_DIR_PATH/romfs_stage"

if [ ! -f "$ELF_PATH" ]; then
  echo "ELF not found: $ELF_PATH"
  echo "Please build Switch once first."
  exit 1
fi

if ! command -v elf2nro >/dev/null 2>&1; then
  echo "elf2nro not found in PATH. Please open a devkitPro shell first."
  exit 1
fi

echo "[romfs] Staging assets to $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
tar -C "$REPO_ROOT/res" -cf - . | tar -C "$STAGE_DIR" -xf -
mkdir -p "$STAGE_DIR/mod"
tar -C "$REPO_ROOT/mod" -cf - . | tar -C "$STAGE_DIR/mod" -xf -
find "$STAGE_DIR" -name ".gitignore" -delete

echo "[romfs] Packing $NRO_PATH"
elf2nro "$ELF_PATH" "$NRO_PATH" \
  --icon="$ICON_PATH" \
  --name="$APP_NAME" \
  --author="$AUTHOR" \
  --romfsdir="$STAGE_DIR"

echo "[romfs] Done: $NRO_PATH"
