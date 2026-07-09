#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config
# -----------------------------
FPC_SRC_DIR="${HOME}/fpcsrc"
FPC_BRANCH="${FPC_BRANCH:-release_3_2_2}"
CROSS_SHIM_DIR="${HOME}/cross-go32v2/bin"
FPC_USER_CFG="${HOME}/.fpc.cfg"
SHELL_RC="${HOME}/.bashrc"

append_once() {
  local line="$1"
  local file="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

try_install_pkg() {
  local pkg="$1"
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    echo "===> Installing package: $pkg"
    sudo apt-get install -y "$pkg"
    return 0
  fi
  return 1
}

find_djgpp_prefix() {
  local prefixes=(
    i586-pc-msdosdjgpp
    i686-pc-msdosdjgpp
    i386-pc-msdosdjgpp
  )

  for p in "${prefixes[@]}"; do
    if command -v "${p}-as" >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done

  return 1
}

echo "===> Installing base packages"
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  git \
  wget \
  unzip \
  make \
  bison \
  flex \
  fp-compiler \
  fp-units-base \
  fp-utils

# -----------------------------
# Install DJGPP toolchain from apt if available
# -----------------------------
echo "===> Trying to install DJGPP cross tools"
FOUND_ANY=0
for pkg in gcc-djgpp binutils-djgpp djgpp-dev; do
  if try_install_pkg "$pkg"; then
    FOUND_ANY=1
  fi
done

if [ "$FOUND_ANY" -eq 0 ]; then
  echo
  echo "ERROR: No DJGPP packages were found in apt."
  echo "Try these commands manually to inspect availability:"
  echo "  apt-cache search djgpp"
  echo "  apt-cache search msdosdjgpp"
  exit 1
fi

# -----------------------------
# Build shim names FPC expects
# -----------------------------
echo "===> Looking for installed DJGPP binutils prefix"
if ! DJGPP_PREFIX="$(find_djgpp_prefix)"; then
  echo
  echo "ERROR: DJGPP assembler not found after package install."
  echo "Look for these commands manually:"
  echo "  compgen -c | grep djgpp"
  echo "  compgen -c | grep msdos"
  exit 1
fi

echo "===> Found DJGPP prefix: ${DJGPP_PREFIX}"

mkdir -p "${CROSS_SHIM_DIR}"

for tool in as ld ar ranlib strip nm objdump; do
  if command -v "${DJGPP_PREFIX}-${tool}" >/dev/null 2>&1; then
    ln -sf "$(command -v "${DJGPP_PREFIX}-${tool}")" "${CROSS_SHIM_DIR}/i386-go32v2-${tool}"
  fi
done

export PATH="${CROSS_SHIM_DIR}:${PATH}"

echo "===> Verifying shimmed tools"
command -v i386-go32v2-as
command -v i386-go32v2-ld
command -v i386-go32v2-ar

# -----------------------------
# Clone FPC source
# -----------------------------
echo "===> Cloning Free Pascal source"
if [ ! -d "${FPC_SRC_DIR}" ]; then
  git clone --depth 1 --branch "${FPC_BRANCH}" \
    https://gitlab.com/freepascal.org/fpc/source.git \
    "${FPC_SRC_DIR}"
else
  echo "===> FPC source already present"
fi

# -----------------------------
# Build GO32v2 cross compiler
# -----------------------------
echo "===> Building ppcross386 for DOS"
cd "${FPC_SRC_DIR}"

# Clean any previous partial build states
make clean OS_TARGET=go32v2 CPU_TARGET=i386

# Build the cross-compiler and the DOS units
make crossall \
  OS_TARGET=go32v2 \
  CPU_TARGET=i386 \
  BINUTILSPREFIX=i386-go32v2-

# Install explicitly into /usr so the apt-installed 'fpc' wrapper can see it
sudo make crossinstall \
  OS_TARGET=go32v2 \
  CPU_TARGET=i386 \
  BINUTILSPREFIX=i386-go32v2- \
  INSTALL_PREFIX=/usr

# -----------------------------
# Persist environment
# -----------------------------
echo "===> Updating shell config"
append_once 'export PATH="$HOME/cross-go32v2/bin:$PATH"' "${SHELL_RC}"

echo "===> Updating user FPC config"
mkdir -p "$(dirname "$FPC_USER_CFG")"
touch "${FPC_USER_CFG}"

# Clean out old blocks if re-running the script
sed -i '/# GO32v2 cross compile/,$d' "${FPC_USER_CFG}" 2>/dev/null || true

# Append the required search paths for the cross compiler
cat <<EOF >> "${FPC_USER_CFG}"
# GO32v2 cross compile
#ifdef cpui386
#ifdef go32v2
-Fu/usr/lib/fpc/\$fpcversion/units/\$fpctarget/*
-Fl/usr/lib/fpc/\$fpcversion/units/\$fpctarget/*
-FD${HOME}/cross-go32v2/bin
-XPi386-go32v2-
#endif
#endif
EOF

# -----------------------------
# Final checks
# -----------------------------
echo "===> Final checks"

# When building x86_64 -> i386, FPC names the binary 'ppcross386'
if [ -f "/usr/lib/fpc/3.2.2/ppcross386" ]; then
  echo "Success: ppcross386 found in compiler directory!"
else
  echo "Warning: ppcross386 not in standard directory; checking alternative paths..."
  find /usr -name ppcross386 2>/dev/null || true
fi

cat <<'EOF'

Setup complete.

Open a new shell or run:
  source ~/.bashrc

Then test your project build target:
  fpc -Tgo32v2 hello.pas

EOF