#!/usr/bin/env bash
# Запускается внутри chroot во время сборки JAG Linux
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=ru_RU.UTF-8

# ─── APT sources ──────────────────────────────────────────────────────────────
cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu noble           main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates   main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security  main restricted universe multiverse
EOF

apt-get update -qq

# ─── Локаль ───────────────────────────────────────────────────────────────────
apt-get install -y locales
sed -i 's/# ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=ru_RU.UTF-8

# ─── Ядро и базовые пакеты ────────────────────────────────────────────────────
apt-get install -y \
    linux-image-generic \
    linux-headers-generic \
    initramfs-tools \
    casper \
    lupin-casper \
    systemd \
    systemd-sysv \
    dbus \
    sudo \
    bash \
    nano \
    vim \
    curl \
    wget \
    git \
    openssh-client \
    network-manager \
    net-tools \
    iproute2 \
    iputils-ping \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    gnupg \
    lsb-release

# ─── KDE Plasma ───────────────────────────────────────────────────────────────
apt-get install -y \
    kde-plasma-desktop \
    sddm \
    konsole \
    dolphin \
    kate \
    ark \
    gwenview \
    okular \
    plasma-nm \
    plasma-pa \
    plasma-widgets-addons \
    kscreen \
    powerdevil \
    bluedevil \
    breeze \
    breeze-gtk-theme \
    kde-config-gtk-style \
    fonts-noto \
    fonts-noto-cjk \
    fonts-liberation

# ─── Инструменты разработки ───────────────────────────────────────────────────
apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    python3 \
    python3-pip \
    gdb

# ─── Браузер и приложения ─────────────────────────────────────────────────────
apt-get install -y \
    firefox \
    libreoffice \
    vlc \
    gimp \
    htop \
    neofetch \
    gparted \
    timeshift

# ─── Live-система (casper) ────────────────────────────────────────────────────
apt-get install -y \
    casper \
    discover \
    laptop-detect \
    os-prober

# ─── SDDM автологин ───────────────────────────────────────────────────────────
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << 'EOF'
[Autologin]
User=jag
Session=plasma
EOF

# ─── Пользователь live ────────────────────────────────────────────────────────
useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev jag
echo "jag:jag" | chpasswd
echo "root:root" | chpasswd

# Без пароля для sudo в live
echo "jag ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jag

# ─── Hostname и hosts ─────────────────────────────────────────────────────────
echo "jaglinux" > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   jaglinux
::1         localhost ip6-localhost ip6-loopback
EOF

# ─── Раскладка клавиатуры ─────────────────────────────────────────────────────
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << 'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,ru"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF

# ─── Часовой пояс ─────────────────────────────────────────────────────────────
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime

# ─── Включить сервисы ─────────────────────────────────────────────────────────
systemctl enable sddm
systemctl enable NetworkManager

# ─── Отключить ненужное в live ────────────────────────────────────────────────
systemctl disable apt-daily.timer          2>/dev/null || true
systemctl disable apt-daily-upgrade.timer  2>/dev/null || true
systemctl disable motd-news.timer          2>/dev/null || true

# ─── Neofetch конфиг ──────────────────────────────────────────────────────────
mkdir -p /home/jag/.config/neofetch
cat > /home/jag/.config/neofetch/config.conf << 'EOF'
print_info() {
    info title
    info underline
    info "OS"         distro
    info "Kernel"     kernel
    info "Uptime"     uptime
    info "Packages"   packages
    info "Shell"      shell
    info "DE"         de
    info "WM"         wm
    info "Terminal"   term
    info "CPU"        cpu
    info "Memory"     memory
    prin ""
    prin "JAG Linux — Just Are Good Linux"
}
distro_shorthand="off"
os_arch="on"
EOF
chown -R jag:jag /home/jag/.config

# ─── .bashrc для jag ──────────────────────────────────────────────────────────
cat >> /home/jag/.bashrc << 'EOF'

# JAG Linux
neofetch
alias ll='ls -alF'
alias la='ls -A'
alias install='sudo apt install'
alias update='sudo apt update && sudo apt upgrade'
EOF

# ─── Очистка ──────────────────────────────────────────────────────────────────
apt-get autoremove -y
apt-get clean
rm -rf /tmp/* /var/tmp/*
rm -f /tmp/configure.sh
