#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-v0.3.13}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
TMP_DIR="${TMPDIR:-/tmp}/agent-mail-install.$$"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) TARGET="aarch64-apple-darwin" ;;
  Darwin-x86_64) TARGET="x86_64-apple-darwin" ;;
  Linux-aarch64|Linux-arm64) TARGET="aarch64-unknown-linux-gnu" ;;
  Linux-x86_64) TARGET="x86_64-unknown-linux-gnu" ;;
  *)
    echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

ASSET="mcp-agent-mail-${TARGET}.tar.xz"
BASE_URL="https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/${VERSION}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR" "$INSTALL_DIR"

echo "Installing Agent Mail $VERSION for $TARGET"
echo "Download: $BASE_URL/$ASSET"

curl -fsSL "$BASE_URL/$ASSET" -o "$TMP_DIR/$ASSET"
curl -fsSL "$BASE_URL/$ASSET.sha256" -o "$TMP_DIR/$ASSET.sha256"

expected="$(awk '{print $1}' "$TMP_DIR/$ASSET.sha256")"
actual="$(shasum -a 256 "$TMP_DIR/$ASSET" | awk '{print $1}')"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "Checksum mismatch for $ASSET" >&2
  echo "expected: ${expected:-<empty>}" >&2
  echo "actual:   $actual" >&2
  exit 1
fi
echo "Checksum verified: $actual"

mkdir -p "$TMP_DIR/extract"
tar -xJf "$TMP_DIR/$ASSET" -C "$TMP_DIR/extract"

for bin in mcp-agent-mail am; do
  found="$(find "$TMP_DIR/extract" -type f -name "$bin" -perm -111 | head -n 1 || true)"
  if [[ -z "$found" ]]; then
    echo "Expected executable not found in archive: $bin" >&2
    find "$TMP_DIR/extract" -maxdepth 3 -type f >&2
    exit 1
  fi
  install -m 0755 "$found" "$INSTALL_DIR/$bin"
  echo "Installed $bin to $INSTALL_DIR/$bin"
done

"$INSTALL_DIR/mcp-agent-mail" --version
"$INSTALL_DIR/am" --version
