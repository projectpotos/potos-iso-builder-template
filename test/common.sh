#!/usr/bin/env bash
#
# Shared helpers for the test scripts.
#
# Derives the VM name, ISO filename and passwords from input/config.yml so the
# scripts work unchanged in any client repo created from this template.
# Requires yq.
#
# shellcheck disable=SC2034  # variables are consumed by the sourcing scripts

# Use QEMU user session
export LIBVIRT_DEFAULT_URI=qemu:///session

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${TEST_DIR}")"
CONFIG_FILE="${REPO_DIR}/input/config.yml"
OUTPUT_DIR="${REPO_DIR}/output"

if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq not found; the test scripts need it to read input/config.yml" >&2
    exit 1
fi

# cfg <expression>: read a scalar from input/config.yml, e.g. `cfg .output.iso_filename`
cfg() {
    yq -r "$1 // \"\"" "${CONFIG_FILE}" 2>/dev/null
}

CLIENT_SHORT="$(cfg .client_name.short)"
CLIENT_SHORT="${CLIENT_SHORT:-potos}"

VM_NAME="${VM_NAME:-${CLIENT_SHORT}-testvm}"

ISO_FILENAME="$(cfg .output.iso_filename)"
ISO_FILENAME="${ISO_FILENAME:-${CLIENT_SHORT}-installer.iso}"
ISO_PATH="${OUTPUT_DIR}/${ISO_FILENAME}"

DISK_PATH="${HOME}/.local/share/libvirt/images/${VM_NAME}.qcow2"
