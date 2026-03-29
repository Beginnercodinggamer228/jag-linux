#!/usr/bin/env bash
# JAG Linux — запуск ISO в QEMU
# Использование:
#   bash scripts/run_qemu.sh           # BIOS режим
#   UEFI=1 bash scripts/run_qemu.sh    # UEFI режим

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-$(ls -t "${SCRIPT_DIR}/output"/jaglinux-*.iso 2>/dev/null | head -1)}"
DISK_IMG="/tmp/jag-test-disk.qcow2"

[[ -f "${ISO}" ]] || { echo "ISO не найден: ${ISO}"; exit 1; }

echo "Запуск: ${ISO}"

# Создать тестовый диск
if [[ ! -f "${DISK_IMG}" ]]; then
    qemu-img create -f qcow2 "${DISK_IMG}" 20G
fi

# UEFI или BIOS
if [[ "${UEFI:-0}" == "1" ]]; then
    OVMF=""
    for f in /usr/share/ovmf/OVMF.fd /usr/share/edk2/ovmf/OVMF_CODE.fd \
              /usr/share/qemu/OVMF.fd; do
        [[ -f "$f" ]] && OVMF="$f" && break
    done
    [[ -n "${OVMF}" ]] || { echo "OVMF не найден, установите ovmf"; exit 1; }
    BIOS_ARGS=(-bios "${OVMF}")
    echo "Режим: UEFI"
else
    BIOS_ARGS=()
    echo "Режим: BIOS"
fi

qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp 2 \
    -m 4G \
    "${BIOS_ARGS[@]}" \
    -cdrom "${ISO}" \
    -drive file="${DISK_IMG}",format=qcow2,if=virtio \
    -boot order=d \
    -vga virtio \
    -display gtk,zoom-to-fit=on \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -usb \
    -device usb-tablet
