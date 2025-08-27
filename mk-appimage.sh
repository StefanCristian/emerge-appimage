#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <category/pkg> <binary_name> [AppName] [march_option]"
  echo "Example: $0 app-misc/jq jq JQ"
  echo "         $0 app-misc/jq jq JQ native    # Force -march=native"
  echo "         $0 app-misc/jq jq JQ x86-64   # Force -march=x86-64"
  echo "         $0 app-misc/jq jq JQ detect   # Auto-detect from system"
  exit 1
fi

PKG="$1"
BIN_NAME="$2"
APPNAME="${3:-$(echo "$BIN_NAME" | tr '[:lower:]' '[:upper:]')}"
MARCH_OPTION="${4:-detect}"
ARCH="$(uname -m)"

WORKDIR="$(pwd)/_appimg_${BIN_NAME}"
APPDIR="${WORKDIR}/${APPNAME}.AppDir"

rm -rf "$WORKDIR"
mkdir -p "${APPDIR}/usr"

case "${MARCH_OPTION}" in
  detect)
    CURRENT_CFLAGS="$(portageq envvar CFLAGS 2>/dev/null || echo "")"
    if [[ "${CURRENT_CFLAGS}" =~ -march=([^[:space:]]+) ]]; then
      DETECTED_MARCH="${BASH_REMATCH[1]}"
      echo "==> Detected current -march=${DETECTED_MARCH} from system CFLAGS"
      if [[ "${DETECTED_MARCH}" == "native" ]]; then
        echo "    Warning: -march=native detected. AppImage may not be portable!"
      fi
    else
      echo "==> No specific -march detected in system CFLAGS"
      DETECTED_MARCH=""
    fi
    ;;
  native)
    echo "==> Forcing -march=native compilation (not portable!)"
    export CFLAGS="${CFLAGS:-} -march=native -mtune=native"
    export CXXFLAGS="${CXXFLAGS:-} -march=native -mtune=native"
    ;;
  x86-64|x86-64-v2|x86-64-v3|x86-64-v4)
    echo "==> Forcing -march=${MARCH_OPTION} compilation"
    export CFLAGS="${CFLAGS:-} -march=${MARCH_OPTION}"
    export CXXFLAGS="${CXXFLAGS:-} -march=${MARCH_OPTION}"
    ;;
  *)
    echo "==> Using custom -march=${MARCH_OPTION} compilation"
    export CFLAGS="${CFLAGS:-} -march=${MARCH_OPTION}"
    export CXXFLAGS="${CXXFLAGS:-} -march=${MARCH_OPTION}"
    ;;
esac

echo "==> Installing ${PKG} into ${APPDIR}/usr via Portage..."

sudo ROOT="${APPDIR}/usr" \
     emerge -v --root="${APPDIR}/usr" --root-deps=rdeps \
     --oneshot --buildpkg=n --binpkg-respect-use=y "${PKG}"


BIN_PATH="$(command -v --posix true >/dev/null 2>&1 || true; \
            find "${APPDIR}/usr" -type f -perm -0100 -name "${BIN_NAME}" | head -n1)"
if [[ -z "${BIN_PATH}" ]]; then
  echo "Could not find ${BIN_NAME} under ${APPDIR}/usr; adjust BIN_NAME or inspect files."
  exit 2
fi

echo "==> Creating AppRun..."
cat > "${APPDIR}/AppRun" <<'EOF'
#!/bin/sh
# Use $APPDIR set by AppImage runtime
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="$HERE"
# Prefer our libs
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/usr/lib64:$LD_LIBRARY_PATH"
# Add our bin first
export PATH="$APPDIR/usr/bin:$PATH"
# Execute the binary name from the .desktop Exec= line (first arg or default)
exec "$APPDIR/usr/bin/__BIN__" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

sed -i "s/__BIN__/$(basename "${BIN_PATH}")/" "${APPDIR}/AppRun"

echo "==> Creating desktop file and icon..."
mkdir -p "${APPDIR}/usr/share/applications" "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
cat > "${APPDIR}/${APPNAME}.desktop" <<EOF
[Desktop Entry]
Name=${APPNAME}
Exec=$(basename "${BIN_PATH}")
Icon=${APPNAME}
Type=Application
Categories=Utility;
Terminal=false
EOF


convert -size 256x256 xc:white -gravity center -pointsize 64 \
        -draw "text 0,0 '${APPNAME:0:2}'" "${APPDIR}/${APPNAME}.png" 2>/dev/null || true

echo "==> Auditing shared libraries..."
mkdir -p "${APPDIR}/usr/lib" "${APPDIR}/usr/lib64"
if command -v lddtree >/dev/null 2>&1; then
  mapfile -t LIBS < <(lddtree -l "${BIN_PATH}" | tr ' ' '\n' | sort -u)
  for L in "${LIBS[@]}"; do
    [[ -e "$L" ]] || continue
    BAS="$(basename "$L")"
    case "$BAS" in
      ld-linux*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libnsl.so.*|libresolv.so.*|libcrypt.so.*)
        continue
        ;;
    esac
    TGT_DIR="${APPDIR}/usr/$(basename "$(dirname "$L")")"
    mkdir -p "$TGT_DIR"
    rsync -a "$L" "$TGT_DIR/"
  done
else
  echo "Note: Install pax-utils for lddtree to auto-bundle libs: emerge -v app-misc/pax-utils"
fi

echo "==> Ensuring binary is in usr/bin..."
mkdir -p "${APPDIR}/usr/bin"
if [[ "${BIN_PATH}" != "${APPDIR}/usr/bin/"* ]]; then
  ln -sf "$(realpath --relative-to="${APPDIR}/usr/bin" "${BIN_PATH}")" "${APPDIR}/usr/bin/$(basename "${BIN_PATH}")"
fi

echo "==> Fetching appimagetool..."
cd "${WORKDIR}"
if [[ ! -x appimagetool-${ARCH}.AppImage ]]; then
  wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-"${ARCH}".AppImage
  chmod +x appimagetool-"${ARCH}".AppImage
fi

echo "==> Building AppImage..."
PORTAGE_ARCH="$(portageq envvar ARCH 2>/dev/null || echo "")"
case "${PORTAGE_ARCH}" in
  amd64) APPIMAGE_ARCH="x86_64" ;;
  x86)   APPIMAGE_ARCH="i386" ;;
  arm64) APPIMAGE_ARCH="aarch64" ;;
  arm)   APPIMAGE_ARCH="armhf" ;;
  *)     APPIMAGE_ARCH="${ARCH}" ;;
esac

ARCH="${APPIMAGE_ARCH}" ./appimagetool-"${ARCH}".AppImage "${APPNAME}.AppDir"

echo "==> Done."
ls -1 "${WORKDIR}"/*.AppImage
