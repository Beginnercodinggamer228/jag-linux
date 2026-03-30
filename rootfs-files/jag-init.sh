#!/bin/sh
# JAG Linux - Alpine initramfs customization
# This runs inside the initramfs

# Fix /etc/issue
cat > /etc/issue << 'ISSEOF'
Jag Linux v1.0 beta (based on Alpine Linux)
All copying is permitted with the indication of the author
Type jag-help for help or visit: https://jaglinux.example.com

ISSEOF

# Fix inittab for autologin on tty1
if [ -f /etc/inittab ]; then
    sed -i 's|tty1::respawn:/sbin/getty.*|tty1::respawn:/sbin/getty -n -l /bin/sh 38400 tty1|' /etc/inittab
fi
