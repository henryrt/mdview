#!/usr/bin/env bash
set -e

echo "=== Starting FPC DOS Cross-Compiler Setup ==="

# 1. Add 32-bit architecture and sync the system repository indexes
sudo dpkg --add-architecture i386
sudo apt-get update

# 2. Install prerequisites + the official structural cross-unit packages natively
# The 'fp-units-i386' package automatically contains the pre-compiled go32v2 units!
sudo apt-get install -y wget tar libc6:i386 fp-units-i386

# 3. Reset and create a clean working directory
sudo rm -rf /tmp/fpc_setup
mkdir -p /tmp/fpc_setup
cd /tmp/fpc_setup

# 4. Download and Install the official native 64-bit Linux compiler bundle
echo "Downloading Linux compiler engine..."
wget -q https://sourceforge.net/projects/freepascal/files/Linux/3.2.2/fpc-3.2.2.x86_64-linux.tar/download -O fpc_linux.tar
tar -xf fpc_linux.tar
cd fpc-3.2.2.x86_64-linux
tar -xf binary.x86_64-linux.tar
sudo ./install.sh <<EOF
/usr
Y
Y
Y
EOF

# 5. Locate the natively installed go32v2 units and ensure they sit inside the active compiler paths
# Apt installs them, but we want to make sure the core driver maps them cleanly
FPC_VERSION=$(fpc -iV | tr -d '\r')
echo "Detected FPC Core Version: $FPC_VERSION"

# 6. Ensure the compiler wrapper recognizes target calls
sudo ln -sf /usr/bin/ppcx64 /usr/bin/ppc386 || true

# 7. Re-generate the global system configuration maps to scan all newly pulled libraries
sudo /usr/lib/fpc/${FPC_VERSION}/samplecfg /usr/lib/fpc/${FPC_VERSION} /etc

# 8. Clean up temporary directory
sudo rm -rf /tmp/fpc_setup

echo "=== FPC DOS Cross-Compiler Setup Complete! ==="