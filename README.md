# JAG Linux 🐆
**Just Are Good Linux** — дистрибутив на базе Ubuntu 24.04 LTS с KDE Plasma.

## Особенности
- Основан на Ubuntu 24.04 LTS (Noble Numbat)
- Рабочий стол KDE Plasma 6 с темой Breeze Dark
- Русский язык по умолчанию (раскладка us/ru, переключение Alt+Shift)
- Live-режим с автологином пользователя `jag`
- Инструменты разработки: gcc, g++, make, cmake, python3, git
- Браузер Firefox, LibreOffice, VLC, GIMP
- Загрузка BIOS (isolinux) и UEFI (GRUB)

## Сборка

### Требования
- Ubuntu 22.04+ или Debian 12+ (или WSL2 с Ubuntu)
- Права root
- ~10 GB свободного места

### Зависимости (устанавливаются автоматически)
```
debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools isolinux
```

### Запуск сборки
```bash
# Полная сборка
sudo bash build.sh

# Минимальная сборка (только базовая система, без KDE)
sudo bash build.sh

# Войти в chroot для отладки
sudo bash build.sh chroot

# Очистить рабочие файлы
sudo bash build.sh clean
```

Готовый ISO будет в `output/jaglinux-1.0-amd64.iso`

## Тестирование в QEMU

```bash
# BIOS режим
bash scripts/run_qemu.sh

# UEFI режим (нужен пакет ovmf)
UEFI=1 bash scripts/run_qemu.sh

# Указать ISO вручную
bash scripts/run_qemu.sh /path/to/jaglinux.iso
```

## Структура проекта
```
jag-linux/
├── build.sh                        # главный скрипт сборки
├── config/
│   ├── etc/                        # конфиги системы (копируются в rootfs)
│   │   ├── hostname
│   │   ├── locale.conf
│   │   └── NetworkManager/
│   ├── grub/grub.cfg               # конфиг GRUB (UEFI)
│   ├── isolinux/isolinux.cfg       # конфиг isolinux (BIOS)
│   └── wallpapers/                 # обои рабочего стола
├── scripts/
│   ├── configure_chroot.sh         # настройка системы внутри chroot
│   └── run_qemu.sh                 # запуск в QEMU для тестирования
├── rootfs/                         # рабочая директория (создаётся при сборке)
└── output/                         # готовый ISO
```

## Учётные данные live-системы
| Пользователь | Пароль |
|---|---|
| `jag` | `jag` |
| `root` | `root` |

## Лицензия
GPL-3.0
