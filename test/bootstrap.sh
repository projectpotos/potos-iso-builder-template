#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/common.sh
source "${SCRIPT_DIR}/common.sh"

OS_VARIANT="${OS_VARIANT:-fedora43}"

# Secure Boot capable firmware + blank vars store, per distro. Override with
# OVMF_CODE / OVMF_VARS_TEMPLATE if your distro ships them elsewhere.
if [ -z "${OVMF_CODE}" ] || [ -z "${OVMF_VARS_TEMPLATE}" ]; then
    for pair in \
        "/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd" \
        "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd /usr/share/edk2/ovmf/OVMF_VARS.fd" \
        "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/OVMF/OVMF_VARS_4M.fd"; do
        read -r code vars <<< "${pair}"
        if [ -f "${code}" ] && [ -f "${vars}" ]; then
            OVMF_CODE="${code}"
            OVMF_VARS_TEMPLATE="${vars}"
            break
        fi
    done
fi
if [ -z "${OVMF_CODE}" ] || [ ! -f "${OVMF_CODE}" ]; then
    echo "ERROR: no Secure Boot OVMF firmware found; install edk2-ovmf and/or set OVMF_CODE / OVMF_VARS_TEMPLATE" >&2
    exit 1
fi

# Some distros (e.g. Arch) ship only a blank (un-enrolled) vars store, so Secure
# Boot would come up in Setup Mode. Pre-enroll the standard RH/Microsoft keys once
# and reuse the result as the nvram template so each new VM boots in User Mode.
ENROLLED_VARS="${SCRIPT_DIR}/OVMF_VARS.secboot.4m.fd"

if [ ! -f "${ISO_PATH}" ]; then
    echo "ERROR: output ISO not found at ${ISO_PATH}" >&2
    echo "       Build it first: task build:all" >&2
    exit 1
fi

if [ ! -f "${ENROLLED_VARS}" ]; then
    if ! command -v virt-fw-vars >/dev/null 2>&1; then
        echo "ERROR: virt-fw-vars not found; cannot enroll Secure Boot keys." >&2
        echo "       Install it with: pipx install virt-firmware (or: pip install virt-firmware)" >&2
        exit 1
    fi
    echo "==> Generating Secure Boot vars store with enrolled RH/Microsoft keys..."
    virt-fw-vars \
        --input "${OVMF_VARS_TEMPLATE}" \
        --output "${ENROLLED_VARS}" \
        --enroll-redhat --secure-boot
fi

echo "==> Installing VM '${VM_NAME}' from ${ISO_PATH} (os-variant: ${OS_VARIANT})"

virt-install \
    --name "${VM_NAME}" \
    --ram 4096 \
    --vcpus 2 \
    --disk "path=${DISK_PATH},size=20,format=qcow2" \
    --os-variant "${OS_VARIANT}" \
    --cdrom "${ISO_PATH}" \
    --network user \
    --graphics spice \
    --noautoconsole \
    --boot loader="${OVMF_CODE}",loader.readonly=yes,loader.type=pflash,loader.secure=yes,nvram.template="${ENROLLED_VARS}",nvram.templateFormat=raw \
    --features smm.state=on \
    --machine q35 \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --wait -1

echo "==> Installation finished. Detaching install ISO..."
# Find and detach the cdrom device so the VM boots from disk on next start
CDROM_DEV=$(virsh domblklist "${VM_NAME}" --details \
    | awk '$2 == "cdrom" && $4 != "-" { print $3 }' | head -n1)
if [ -n "${CDROM_DEV}" ]; then
    virsh change-media "${VM_NAME}" "${CDROM_DEV}" --eject --config
    echo "==> Ejected cdrom device '${CDROM_DEV}'."
fi

MOK_PASSWORD="$(cfg .uki.mok_password)"
MOK_PASSWORD="${MOK_PASSWORD:-potos}"

echo "==> Booting installed VM..."
echo "==> ACTION REQUIRED: attach a console and complete MOK enrollment promptly:"
echo "      virt-viewer --connect qemu:///session ${VM_NAME}"
echo "    At MokManager: Enroll MOK -> Continue -> Yes -> password '${MOK_PASSWORD}', then reboot."
echo "    Missed it / got a 0x1A screen? Enroll non-interactively instead:"
echo "      task test:enroll-mok"
if ! start_out=$(virsh start "${VM_NAME}" 2>&1); then
    if ! grep -q "Domain is already active" <<< "${start_out}"; then
        echo "ERROR: Failed to start VM '${VM_NAME}'" >&2
        echo "${start_out}" >&2
        exit 1
    fi
fi

# Poll until running (up to 60 s)
for _ in $(seq 1 12); do
    STATE=$(virsh domstate "${VM_NAME}" 2>/dev/null || true)
    if [ "${STATE}" = "running" ]; then
        echo "==> VM '${VM_NAME}' is running."
        # test if notify send exists
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "VM '${VM_NAME}' is running. Please complete MOK enrollment in the VM console."
        fi
        exit 0
    fi
    sleep 5
done

echo "ERROR: VM '${VM_NAME}' did not reach running state in time." >&2
virsh dominfo "${VM_NAME}" >&2
exit 1
