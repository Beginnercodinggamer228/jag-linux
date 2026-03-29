#!/usr/bin/env bash
# JAG Linux — главный скрипт сборки ISO
# Основан на Ubuntu 24.04 LTS (Noble)
# Запускать от root на Ubuntu/Debian хосте или в WSL2
#
# Использование:
#   sudo bash build.sh          # полная сборка
#   sudo bash build.sh clean    # очистить рабочие файлы
#   sudo bash build.sh chroot   # войти в chroot для отладки

set -euo pipefail

# ─── Конфигурация ────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOTFS="${SCRIPT_DIR}/rootfs"
readonly OUTPUT="${SCRIPT_DIR}/output"
readonly CONFIG="${SCRIPT_DIR}/config"

readonly DISTRO_NAME="JAG Linux"
readonly DISTRO_VERSION="1.0"
readonly DISTRO_CODENAME="jaguar"
readonly ISO_NAME="jaglinux-${DISTRO_VERSION}-amd64.iso"
readonly UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
readonly UBUNTU_RELEASE="noble"   # Ubuntu 24.04 LTS

# ─── Цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[JAG]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ─── Проверки ─────────────────────────────────────────────────────────────────
check_root() {
    [[ "${EUID}" -eq 0 ]] || die "Запустите от root: sudo bash build.sh"
}

check_deps() {
    log "Проверка зависимостей..."
    local deps=(debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools)
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "${dep%%-*}" &>/dev/null || dpkg -l "${dep}" &>/dev/null || missing+=("${dep}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Установка зависимостей: ${missing[*]}"
        apt-get update -qq
        apt-get install -y "${missing[@]}"
    fi
    ok "Зависимости готовы"
}

# ─── Очистка ──────────────────────────────────────────────────────────────────
clean() {
    log "Очистка..."
    if mountpoint -q "${ROOTFS}/proc" 2>/dev/null; then
        umount -lf "${ROOTFS}/proc" 2>/dev/null || true
        umount -lf "${ROOTFS}/sys"  2>/dev/null || true
        umount -lf "${ROOTFS}/dev"  2>/dev/null || true
    fi
    rm -rf "${ROOTFS}" "${SCRIPT_DIR}/iso_root"
    ok "Очищено"
}

# ─── Шаг 1: debootstrap ───────────────────────────────────────────────────────
step_debootstrap() {
    if [[ -d "${ROOTFS}/usr" ]]; then
        warn "rootfs уже существует, пропускаем debootstrap"
        return
    fi
    log "Шаг 1/6: debootstrap Ubuntu ${UBUNTU_RELEASE}..."
    debootstrap \
        --arch=amd64 \
        --include=systemd,dbus \
        "${UBUNTU_RELEASE}" \
        "${ROOTFS}" \
        "${UBUNTU_MIRROR}"
    ok "debootstrap завершён"
}

# ─── Шаг 2: настройка chroot ──────────────────────────────────────────────────
step_configure() {
    log "Шаг 2/6: Настройка системы в chroot..."

    # Монтируем виртуальные ФС
    mount --bind /proc "${ROOTFS}/proc"
    mount --bind /sys  "${ROOTFS}/sys"
    mount --bind /dev  "${ROOTFS}/dev"

    # Копируем конфиги
    cp -r "${CONFIG}/etc/." "${ROOTFS}/etc/"

    # Копируем обои
    mkdir -p "${ROOTFS}/usr/share/wallpapers/JAGLinux/contents/images"
    cp "${CONFIG}/wallpapers/"* "${ROOTFS}/usr/share/wallpapers/JAGLinux/contents/images/" 2>/dev/null || true

    # Копируем скелет домашней директории
    cp -r "${CONFIG}/etc/skel/." "${ROOTFS}/etc/skel/" 2>/dev/null || true

    # Запускаем скрипт настройки внутри chroot
    cp "${SCRIPT_DIR}/scripts/configure_chroot.sh" "${ROOTFS}/tmp/configure.sh"
    chmod +x "${ROOTFS}/tmp/configure.sh"
    chroot "${ROOTFS}" /tmp/configure.sh

    # Размонтируем
    umount -lf "${ROOTFS}/proc"
    umount -lf "${ROOTFS}/sys"
    umount -lf "${ROOTFS}/dev"

    ok "Настройка завершена"
}

# ─── Шаг 3: squashfs ──────────────────────────────────────────────────────────
step_squashfs() {
    log "Шаг 3/6: Создание squashfs..."
    mkdir -p "${SCRIPT_DIR}/iso_root/live"
    mksquashfs \
        "${ROOTFS}" \
        "${SCRIPT_DIR}/iso_root/live/filesystem.squashfs" \
        -comp xz \
        -Xbcj x86 \
        -b 1M \
        -noappend \
        -e boot
    ok "squashfs создан: $(du -sh "${SCRIPT_DIR}/iso_root/live/filesystem.squashfs" | cut -f1)"
}

# ─── Шаг 4: ядро и initrd ─────────────────────────────────────────────────────
step_kernel() {
    log "Шаг 4/6: Копирование ядра и initrd..."
    mkdir -p "${SCRIPT_DIR}/iso_root/boot"
    cp "${ROOTFS}/boot/vmlinuz-"*        "${SCRIPT_DIR}/iso_root/boot/vmlinuz"
    cp "${ROOTFS}/boot/initrd.img-"*     "${SCRIPT_DIR}/iso_root/boot/initrd.img"
    ok "Ядро скопировано"
}

# ─── Шаг 5: загрузчики ────────────────────────────────────────────────────────
step_bootloaders() {
    log "Шаг 5/6: Настройка загрузчиков (BIOS + UEFI)..."

    # BIOS — isolinux
    mkdir -p "${SCRIPT_DIR}/iso_root/isolinux"
    cp /usr/lib/ISOLINUX/isolinux.bin          "${SCRIPT_DIR}/iso_root/isolinux/" 2>/dev/null || \
    cp /usr/lib/syslinux/modules/bios/isolinux.bin "${SCRIPT_DIR}/iso_root/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32  "${SCRIPT_DIR}/iso_root/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/menu.c32     "${SCRIPT_DIR}/iso_root/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/libutil.c32  "${SCRIPT_DIR}/iso_root/isolinux/" 2>/dev/null || true
    cp "${CONFIG}/isolinux/isolinux.cfg"       "${SCRIPT_DIR}/iso_root/isolinux/"

    # UEFI — GRUB
    mkdir -p "${SCRIPT_DIR}/iso_root/boot/grub/x86_64-efi"
    cp "${CONFIG}/grub/grub.cfg" "${SCRIPT_DIR}/iso_root/boot/grub/"

    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${SCRIPT_DIR}/iso_root/EFI/boot/bootx64.efi" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${CONFIG}/grub/grub.cfg"

    # EFI образ для xorriso
    mkdir -p "${SCRIPT_DIR}/iso_root/boot/grub"
    dd if=/dev/zero of="${SCRIPT_DIR}/iso_root/boot/grub/efi.img" bs=1M count=4 2>/dev/null
    mkfs.vfat "${SCRIPT_DIR}/iso_root/boot/grub/efi.img"
    mmd -i "${SCRIPT_DIR}/iso_root/boot/grub/efi.img" ::/EFI ::/EFI/boot
    mcopy -i "${SCRIPT_DIR}/iso_root/boot/grub/efi.img" \
        "${SCRIPT_DIR}/iso_root/EFI/boot/bootx64.efi" ::/EFI/boot/

    ok "Загрузчики настроены"
}

# ─── Шаг 6: ISO ───────────────────────────────────────────────────────────────
step_iso() {
    log "Шаг 6/6: Создание ISO..."
    mkdir -p "${OUTPUT}"

    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "JAGLINUX" \
        -full-iso9660-filenames \
        -J -joliet-long \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -append_partition 2 0xef "${SCRIPT_DIR}/iso_root/boot/grub/efi.img" \
        -output "${OUTPUT}/${ISO_NAME}" \
        "${SCRIPT_DIR}/iso_root"

    ok "ISO создан: ${OUTPUT}/${ISO_NAME}"
    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║  ${DISTRO_NAME} ${DISTRO_VERSION} собран успешно!       ║${NC}"
    echo -e "${GREEN}  ║  $(du -sh "${OUTPUT}/${ISO_NAME}" | cut -f1) — ${OUTPUT}/${ISO_NAME}${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Тест в QEMU:"
    echo -e "  ${CYAN}bash scripts/run_qemu.sh${NC}"
}

# ─── Точка входа ──────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}  ║     JAG Linux Build System v${DISTRO_VERSION}          ║${NC}"
    echo -e "${BLUE}  ║     Just Are Good Linux                  ║${NC}"
    echo -e "${BLUE}  ╚══════════════════════════════════════════╝${NC}"
    echo ""

    case "${1:-build}" in
        clean)  check_root; clean ;;
        chroot)
            check_root
            mount --bind /proc "${ROOTFS}/proc"
            mount --bind /sys  "${ROOTFS}/sys"
            mount --bind /dev  "${ROOTFS}/dev"
            chroot "${ROOTFS}" /bin/bash
            umount -lf "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/dev"
            ;;
        build)
            check_root
            check_deps
            step_debootstrap
            step_configure
            step_squashfs
            step_kernel
            step_bootloaders
            step_iso
            ;;
        *)
            die "Неизвестная команда: ${1}. Используйте: build | clean | chroot"
            ;;
    esac
}

main "$@"
