#!/usr/bin/env bash
# Copyright (C) 2025 Stefan Cristian B.
# GPLv2 License
# Script to create an AppImage from a given package in Gentoo
# Usage: mk-appimage.sh <category/pkg> <binary_name> [AppName] [march_option]
# Example: mk-appimage.sh app-misc/jq jq JQ
#          mk-appimage.sh app-misc/jq jq JQ native
#          mk-appimage.sh app-misc/jq jq JQ x86-64
#          mk-appimage.sh app-misc/jq jq JQ detect
#          mk-appimage.sh app-misc/jq jq JQ x86-64


set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <category/pkg> <binary_name> [AppName] [march_option]"
  echo "Example: $0 app-misc/jq jq JQ"
  echo "         $0 app-misc/jq jq JQ native"
  echo "         $0 app-misc/jq jq JQ x86-64"
  echo "         $0 app-misc/jq jq JQ detect"
  echo ""
  echo "Note: Default is x86-64 for maximum portability"
  echo "      System libraries will be bundled into the AppImage"
  exit 1
fi

PKG="$1"
BIN_NAME="$2"
APPNAME="${3:-$(echo "$BIN_NAME" | tr '[:lower:]' '[:upper:]')}"
MARCH_OPTION="${4:-x86-64}"
ARCH="$(uname -m)"

WORKDIR="$(pwd)/_appimg_${BIN_NAME}"
APPDIR="${WORKDIR}/${APPNAME}.AppDir"

rm -rf "$WORKDIR"
mkdir -p "${APPDIR}"

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
    export CFLAGS="$(echo "${CFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CXXFLAGS="$(echo "${CXXFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CFLAGS="${CFLAGS} -march=native -mtune=native"
    export CXXFLAGS="${CXXFLAGS} -march=native -mtune=native"
    ;;
  x86-64|x86-64-v2|x86-64-v3|x86-64-v4)
    echo "==> Using -march=${MARCH_OPTION} compilation for portability"
    export CFLAGS="$(echo "${CFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CXXFLAGS="$(echo "${CXXFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CFLAGS="${CFLAGS} -march=${MARCH_OPTION}"
    export CXXFLAGS="${CXXFLAGS} -march=${MARCH_OPTION}"
    ;;
  *)
    echo "==> Using custom -march=${MARCH_OPTION} compilation"
    export CFLAGS="$(echo "${CFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CXXFLAGS="$(echo "${CXXFLAGS:-}" | sed 's/-march=[^[:space:]]*//')"
    export CFLAGS="${CFLAGS} -march=${MARCH_OPTION}"
    export CXXFLAGS="${CXXFLAGS} -march=${MARCH_OPTION}"
    ;;
esac

echo "==> Installing ${PKG} into ${APPDIR} via Portage..."
sudo ROOT="${APPDIR}" \
     emerge -v --root="${APPDIR}" --nodeps \
     --oneshot --buildpkg=n --binpkg-respect-use=y "${PKG}"

if [[ -d "${APPDIR}/usr" ]]; then
  echo "==> Restructuring to AppImage format..."
  mkdir -p "${APPDIR}_temp/usr"
  mv "${APPDIR}/usr"/* "${APPDIR}_temp/usr/" 2>/dev/null || true
  rm -rf "${APPDIR}"/*
  mv "${APPDIR}_temp/usr" "${APPDIR}/"
  rmdir "${APPDIR}_temp"
fi


BIN_PATH="$(command -v --posix true >/dev/null 2>&1 || true; \
            find "${APPDIR}/usr" -type f -perm -0100 -name "${BIN_NAME}" | head -n1)"
if [[ -z "${BIN_PATH}" ]]; then
  echo "Could not find ${BIN_NAME} under ${APPDIR}/usr; adjust BIN_NAME or inspect files."
  exit 2
fi

echo "==> Creating AppRun..."
cat > "${APPDIR}/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="$HERE"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/usr/lib64:$LD_LIBRARY_PATH"
export PATH="$APPDIR/usr/bin:$PATH"
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
  echo "    Bundling required libraries from system..."
  mapfile -t LIBS < <(lddtree -l "${BIN_PATH}" | tr ' ' '\n' | sort -u)
  for L in "${LIBS[@]}"; do
    [[ -e "$L" ]] || continue
    BAS="$(basename "$L")"
    case "$BAS" in
      ld-linux*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libnsl.so.*|libresolv.so.*|libcrypt.so.*|linux-vdso.so.*|libasound_module_*)
        echo "    Skipping core system lib: ${BAS}"
        continue
        ;;
    esac
    
    LIB_IN_APPDIR="$(find "${APPDIR}/usr" -name "${BAS}" 2>/dev/null | head -n1)"
    if [[ -n "${LIB_IN_APPDIR}" ]]; then
      echo "    Using AppDir version: ${BAS}"
      continue
    fi
    
    echo "    Bundling system library: ${BAS}"
    LIB_DIR="$(dirname "$L")"
    
    if [[ "${LIB_DIR}" == "/usr/lib64" ]]; then
      TGT_DIR="${APPDIR}/usr/lib64"
    elif [[ "${LIB_DIR}" == "/usr/lib" ]]; then
      TGT_DIR="${APPDIR}/usr/lib"
    elif [[ "${LIB_DIR}" == /usr/* ]]; then
      TGT_DIR="${APPDIR}/usr/lib64"
      echo "      -> Moving non-standard library from ${LIB_DIR} to main lib64 directory"
    else
      TGT_DIR="${APPDIR}/usr/lib64"
      echo "      -> Moving system library from ${LIB_DIR} to main lib64 directory"
    fi
    mkdir -p "$TGT_DIR"
    
    if [[ -L "$L" ]]; then
      REAL_FILE="$(readlink -f "$L")"
      REAL_BAS="$(basename "$REAL_FILE")"
      echo "      -> Following symlink to real file: ${REAL_BAS}"
      
      if [[ ! -f "${TGT_DIR}/${REAL_BAS}" ]]; then
        rsync -a "$REAL_FILE" "$TGT_DIR/"
      fi
      
      cd "$TGT_DIR"
      ln -sf "$REAL_BAS" "$BAS"
      cd - >/dev/null
    else
      rsync -a "$L" "$TGT_DIR/"
    fi
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
  wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-"${ARCH}".AppImage
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
