#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "==> Tearing down VM '${VM_NAME}'"

# Destroy the VM if it is still running
STATE=$(virsh domstate "${VM_NAME}" 2>/dev/null || true)
if [ "${STATE}" = "running" ]; then
    echo "==> Destroying running VM..."
    virsh destroy "${VM_NAME}"
fi

# Undefine the domain and remove the disk image
if virsh dominfo "${VM_NAME}" &>/dev/null 2>&1; then
    echo "==> Undefining VM..."
    virsh undefine "${VM_NAME}" --remove-all-storage --nvram 2>/dev/null \
        || virsh undefine "${VM_NAME}" --nvram
fi


echo "==> Teardown complete."
