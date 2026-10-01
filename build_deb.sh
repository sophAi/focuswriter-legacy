#!/usr/bin/env bash
# ==============================================================================
# FocusWriter Legacy - Debian/Ubuntu/Linux Mint .deb Packaging Script
# 
# This script automates building and packaging focuswriter-legacy into a .deb file.
# It supports both system-installed build dependencies and non-root local cache mode.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}"
BUILD_DIR="${SCRIPT_DIR}/build_deb_workspace"
STAGING="${BUILD_DIR}/pkg_staging"
DEPS_ROOT="${SCRIPT_DIR}/.build_deps/root"
PACKAGE_NAME="focuswriter-legacy"
RAW_VERSION="1.7.0"

# --- 1. Detect OS Distribution and Codename ---
DIST_TAG="mint22.3"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" = "linuxmint" ] && [ -n "${VERSION_ID:-}" ]; then
        DIST_TAG="mint${VERSION_ID}"
    elif [ -n "${UBUNTU_CODENAME:-}" ]; then
        DIST_TAG="${UBUNTU_CODENAME}"
    elif [ -n "${VERSION_CODENAME:-}" ]; then
        DIST_TAG="${VERSION_CODENAME}"
    fi
fi

VERSION="${RAW_VERSION}-1~${DIST_TAG}"
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/')"
OUTPUT_DEB="${SCRIPT_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

echo "===================================================================="
echo " Building: ${PACKAGE_NAME} (${VERSION}) [${ARCH}]"
echo " Target OS: ${PRETTY_NAME:-Linux} (Tag: ${DIST_TAG})"
echo "===================================================================="

# --- 2. Check Build Dependencies ---
REQUIRED_DEPS=(
    "build-essential"
    "pkg-config"
    "qtbase5-dev"
    "qtbase5-dev-tools"
    "zlib1g-dev"
    "qtmultimedia5-dev"
    "libhunspell-dev"
    "qttools5-dev-tools"
)

MISSING_DEPS=()
for dep in "${REQUIRED_DEPS[@]}"; do
    if ! dpkg -s "${dep}" 2>/dev/null | grep -q "Status: install ok installed"; then
        MISSING_DEPS+=("${dep}")
    fi
done

USE_LOCAL_DEPS=false

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "Notice: The following build dependencies are not installed in the system:"
    for m in "${MISSING_DEPS[@]}"; do
        echo "  - ${m}"
    done
    echo ""
    echo "You can install them globally with:"
    echo "  sudo apt update && sudo apt install -y ${MISSING_DEPS[*]}"
    echo ""
    echo "-> Falling back to downloading missing dev packages to local cache (.build_deps)..."
    USE_LOCAL_DEPS=true
fi

# Setup local deps if needed
EXTRA_PATH=""
EXTRA_MODULES=""
EXTRA_PKGCONFIG=""
EXTRA_LIBDIR=""

if [ "${USE_LOCAL_DEPS}" = true ]; then
    mkdir -p "${SCRIPT_DIR}/.build_deps/debs" "${DEPS_ROOT}"
    cd "${SCRIPT_DIR}/.build_deps/debs"

    # Only download packages that are missing
    TO_DOWNLOAD=()
    for dep in "${MISSING_DEPS[@]}"; do
        case "${dep}" in
            qtmultimedia5-dev)
                TO_DOWNLOAD+=("qtmultimedia5-dev" "libqt5multimedia5")
                ;;
            libhunspell-dev)
                TO_DOWNLOAD+=("libhunspell-dev")
                ;;
            qttools5-dev-tools)
                TO_DOWNLOAD+=("qttools5-dev-tools")
                ;;
            *)
                TO_DOWNLOAD+=("${dep}")
                ;;
        esac
    done

    if [ ${#TO_DOWNLOAD[@]} -gt 0 ]; then
        echo "-> Downloading missing dev packages via apt-get download..."
        apt-get download "${TO_DOWNLOAD[@]}"
        for deb in *.deb; do
            dpkg -x "$deb" "${DEPS_ROOT}"
        done
    fi

    # Fix hunspell.pc prefix if extracted locally
    if [ -f "${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/pkgconfig/hunspell.pc" ]; then
        sed -i "s|^prefix=/usr|prefix=${DEPS_ROOT}/usr|" "${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/pkgconfig/hunspell.pc"
        # Fix dynamic symlinks for hunspell
        if [ -f /usr/lib/x86_64-linux-gnu/libhunspell-1.7.so.0 ]; then
            ln -sf /usr/lib/x86_64-linux-gnu/libhunspell-1.7.so.0 "${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/libhunspell-1.7.so" 2>/dev/null || true
            ln -sf /usr/lib/x86_64-linux-gnu/libhunspell-1.7.so.0 "${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/libhunspell.so" 2>/dev/null || true
        fi
    fi

    # Fix qt_lib_multimedia.pri if extracted locally
    MODULE_PRI="${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/qt5/mkspecs/modules/qt_lib_multimedia.pri"
    if [ -f "${MODULE_PRI}" ]; then
        cat << EOF > "${MODULE_PRI}"
QT.multimedia.VERSION = 5.15.13
QT.multimedia.name = QtMultimedia
QT.multimedia.module = Qt5Multimedia
QT.multimedia.libs = ${DEPS_ROOT}/usr/lib/x86_64-linux-gnu
QT.multimedia.includes = ${DEPS_ROOT}/usr/include/x86_64-linux-gnu/qt5 ${DEPS_ROOT}/usr/include/x86_64-linux-gnu/qt5/QtMultimedia
QT.multimedia.frameworks =
QT.multimedia.bins = \$\$QT_MODULE_BIN_BASE
QT.multimedia.plugin_types = mediaservice audio video/bufferpool video/gstvideorenderer video/videonode playlistformats resourcepolicy
QT.multimedia.depends = core network gui
QT.multimedia.uses =
QT.multimedia.module_config = v2
QT.multimedia.DEFINES = QT_MULTIMEDIA_LIB
QT.multimedia.enabled_features =
QT.multimedia.disabled_features =
QT_CONFIG += alsa openal pulseaudio
QT_MODULES += multimedia
EOF
    fi

    EXTRA_PATH="${DEPS_ROOT}/usr/lib/qt5/bin:"
    EXTRA_MODULES="${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/qt5/mkspecs/modules"
    EXTRA_PKGCONFIG="${DEPS_ROOT}/usr/lib/x86_64-linux-gnu/pkgconfig:"
    EXTRA_LIBDIR="${DEPS_ROOT}/usr/lib/x86_64-linux-gnu"
fi

# --- 3. Build Project in Clean Workspace ---
echo "-> Preparing clean build workspace: ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${STAGING}"
cd "${BUILD_DIR}"

# Locate qmake
QMAKE_BIN=""
if [ -x /usr/lib/qt5/bin/qmake ]; then
    QMAKE_BIN="/usr/lib/qt5/bin/qmake"
elif command -v qmake >/dev/null 2>&1; then
    QMAKE_BIN="$(command -v qmake)"
else
    echo "Error: qmake not found. Please install qtbase5-dev-tools." >&2
    exit 1
fi

export PATH="${EXTRA_PATH}${PATH}"
if [ -n "${EXTRA_MODULES}" ]; then
    export QMAKEMODULES="${EXTRA_MODULES}"
fi
if [ -n "${EXTRA_PKGCONFIG}" ]; then
    export PKG_CONFIG_PATH="${EXTRA_PKGCONFIG}${PKG_CONFIG_PATH:-}"
fi

echo "-> Configuring with ${QMAKE_BIN}..."
"${QMAKE_BIN}" PREFIX=/usr "${SOURCE_DIR}/focuswriter.pro"

echo "-> Compiling..."
make -j"$(nproc)"

echo "-> Installing to staging directory..."
make install INSTALL_ROOT="${STAGING}"

# --- 4. Process Staging Files ---
echo "-> Post-processing installed files..."

# Strip executable
strip --strip-unneeded "${STAGING}/usr/bin/focuswriter-legacy"

# Compress man page with gzip -9n
if [ -f "${STAGING}/usr/share/man/man1/focuswriter-legacy.1" ]; then
    gzip -9n "${STAGING}/usr/share/man/man1/focuswriter-legacy.1"
fi

# Add Debian copyright and changelog files
DOC_DIR="${STAGING}/usr/share/doc/focuswriter-legacy"
mkdir -p "${DOC_DIR}"

cat << 'EOF' > "${DOC_DIR}/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: FocusWriter
Upstream-Contact: Graeme Gott <graeme@gottcode.org>
Source: https://gottcode.org/focuswriter/

Files: *
Copyright: 2008-2018 Graeme Gott <graeme@gottcode.org>
License: GPL-3.0+

License: GPL-3.0+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 On Debian systems, the complete text of the GNU General Public
 License version 3 can be found in `/usr/share/common-licenses/GPL-3'.
EOF

RFC_DATE="$(date -R)"
cat << EOF > "${DOC_DIR}/changelog.Debian"
${PACKAGE_NAME} (${VERSION}) ${DIST_TAG}; urgency=medium

  * Rebuilt legacy Qt5 FocusWriter for ${PRETTY_NAME:-Linux}.
  * Renamed binary, resources, and desktop entry to focuswriter-legacy
    to prevent conflict with system focuswriter package.
  * Added Qt 5.15 compatibility fix (QPainterPath).
  * Filtered harmless libpng iCCP warning.

 -- FocusWriter Legacy Packager <graeme@gottcode.org>  ${RFC_DATE}
EOF
gzip -9n "${DOC_DIR}/changelog.Debian"

# Set standard Unix permissions
find "${STAGING}" -type d -exec chmod 0755 {} +
find "${STAGING}" -type f -exec chmod 0644 {} +
chmod 0755 "${STAGING}/usr/bin/focuswriter-legacy"

# --- 5. Generate Debian Control & Scripts ---
mkdir -p "${STAGING}/DEBIAN"

# Calculate Installed-Size in KiB
INSTALLED_SIZE=$(du -sk "${STAGING}/usr" | cut -f1)

# Dynamically calculate library dependencies using dpkg-shlibdeps
echo "-> Calculating dynamic library dependencies..."
mkdir -p "${BUILD_DIR}/debian"
echo "libQt5Multimedia 5 libqt5multimedia5 (>= 5.15.1)" > "${BUILD_DIR}/debian/shlibs.local"
touch "${BUILD_DIR}/debian/control"
cd "${BUILD_DIR}"

SHLIB_ARGS=()
if [ -n "${EXTRA_LIBDIR}" ]; then
    SHLIB_ARGS+=("-l${EXTRA_LIBDIR}")
fi

SHLIB_DEPS=$(dpkg-shlibdeps "${SHLIB_ARGS[@]}" -O "${STAGING}/usr/bin/focuswriter-legacy" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')

if [ -z "${SHLIB_DEPS}" ]; then
    echo "Warning: dpkg-shlibdeps could not determine dependencies automatically; using standard defaults."
    SHLIB_DEPS="libc6 (>= 2.34), libgcc-s1 (>= 3.0), libhunspell-1.7-0, libqt5core5t64 (>= 5.15.1) | libqt5core5a, libqt5gui5t64 (>= 5.14.1) | libqt5gui5, libqt5multimedia5 (>= 5.15.1), libqt5network5t64 (>= 5.0.2) | libqt5network5, libqt5printsupport5t64 (>= 5.0.2) | libqt5printsupport5, libqt5widgets5t64 (>= 5.15.1) | libqt5widgets5, libstdc++6 (>= 11), zlib1g (>= 1:1.1.4)"
fi

cat << EOF > "${STAGING}/DEBIAN/control"
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Graeme Gott <graeme@gottcode.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: ${SHLIB_DEPS}
Suggests: hunspell-dictionary, myspell-dictionary
Section: editors
Priority: optional
Homepage: https://gottcode.org/focuswriter/
Description: Fullscreen distraction-free writing program (Legacy Qt5 version)
 FocusWriter is a fullscreen writing program designed to be distraction
 free. You can customize your environment by changing the font, colors,
 and background image to add ambiance.
 .
 This package provides the legacy Qt5 version of FocusWriter, renamed to
 focuswriter-legacy so it can be installed alongside the standard
 FocusWriter package without conflict.
EOF

# postinst script
cat << 'EOF' > "${STAGING}/DEBIAN/postinst"
#!/bin/sh
set -e

if [ "$1" = "configure" ]; then
    if which update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if which gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
    fi
fi

exit 0
EOF
chmod 0755 "${STAGING}/DEBIAN/postinst"

# postrm script
cat << 'EOF' > "${STAGING}/DEBIAN/postrm"
#!/bin/sh
set -e

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if which update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
    if which gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
    fi
fi

exit 0
EOF
chmod 0755 "${STAGING}/DEBIAN/postrm"

# Generate md5sums
cd "${STAGING}"
find usr -type f -exec md5sum {} + > DEBIAN/md5sums
chmod 0644 DEBIAN/md5sums DEBIAN/control

# --- 6. Build .deb package ---
echo "-> Creating .deb package with dpkg-deb..."
dpkg-deb --root-owner-group --build "${STAGING}" "${OUTPUT_DEB}"

# Cleanup temporary build files (keep output deb)
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_DIR}"

echo ""
echo "===================================================================="
echo " Successfully created: ${OUTPUT_DEB}"
echo "===================================================================="
dpkg-deb -I "${OUTPUT_DEB}"

if command -v lintian >/dev/null 2>&1; then
    echo ""
    echo "-> Running Lintian check..."
    lintian "${OUTPUT_DEB}" || true
fi
