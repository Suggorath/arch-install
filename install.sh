#!/usr/bin/env bash

# Arch Linux install - SUGGORATH-PC (plain version: commands only, no checks, no menus)
#
# Firmware:   UEFI 64-bit, CSM off, Secure Boot in Setup Mode (new install) or off (reinstall) during the install
# Disk:       Samsung 970 PRO 512 GB, whole disk erased, GPT (KEEP_HOME="yes": partitions and /home kept)
# Reinstall:  KEEP_HOME="yes" formats only ESP and root, keeps /home, restores the Secure Boot keys from /home
# Partitions: ESP  1 GiB    FAT32  /efi
#             root 100 GiB  ext4   /
#             home rest     ext4   /home
# Names:      partitions found by PARTLABEL, fstab with PARTUUID (genfstab -t PARTUUID)
# Boot:       systemd-boot + UKI (mkinitcpio builds it into /efi/EFI/Linux), root=PARTUUID=...
# Secure Boot: sbctl in the script, own keys + Microsoft + ASUS keys, firmware in Setup Mode before the install
# Windows:    stays on the Corsair disk, first in the boot order; Arch Linux from the firmware boot menu (F8)
# Loader:     bootctl install --no-variables, own "Arch Linux" UEFI entry (efibootmgr), timeout 0, editor no
# Packages:   pacstrap only base linux linux-firmware amd-ucode (default mirrorlist), everything else in chroot
# UKI:        mkinitcpio, preset and /etc/kernel/cmdline written before pacstrap, no fallback, no splash, no quiet
# Time:       Europe/Bratislava, hardware clock in UTC (Windows: RealTimeIsUniversal=1), systemd-timesyncd
# Locale:     LANG en_US.UTF-8 (English messages), all other LC_* sk_SK.UTF-8 (incl. sorting)
# Console:    KEYMAP us, FONT ter-232b (terminus-font), also in the UKI (sd-vconsole hook)
# Hostname:   suggorath-pc (+ /etc/hosts entry), pretty name SUGGORATH-PC, board model in machine-info
# Network:    NetworkManager (Wi-Fi through wpa_supplicant), DNS through systemd-resolved (stub resolv.conf)
# Firewall:   firewalld (nftables), default zone public (ssh, dhcpv6-client), no changes
# Root:       password typed during the install (passwd), root login stays enabled
# User:       suggorath (UID 1000, own group, wheel, bash), sudo for wheel, password typed during the install
# Swap:       zram (zram-generator, ram / 2, zstd), zswap.enabled=0, sysctl tuning for zram, no hibernation, no disk swap
# Extra:      dosfstools, nano, man-db, man-pages, less, bash-completion, pacman-contrib (paccache.timer)
# SSD:        fstrim.timer (weekly TRIM)
# Sleep:      suspend and hibernation disabled (sleep.conf.d)
# NVIDIA:     nvidia-open, lib32-nvidia-utils (multilib), libva-nvidia-driver, nvidia-settings, early loading in the UKI
# Sound:      PipeWire + WirePlumber, pulse/alsa/jack layers, lib32-pipewire, alsa-utils (no firmware needed)
# Bluetooth:  bluez, bluez-utils (bluetoothctl), bluez-obex (file transfer), bluetooth.service, default main.conf
# Desktop:    KDE Plasma (Wayland), Plasma Login Manager, noto-fonts, keyboard us + sk qwerty (Alt+Shift)
# Apps:       konsole, dolphin, ark (+ 7zip, unrar), kcalc, gwenview, skanpage (OCR slk + eng), firefox
# Containers: podman (rootless), podman-compose, short image names from docker.io
# Editor:     zed (+ openbsd-netcat), ~/.config/zed/settings.json "use_podman": true
# Signing:    systemd-boot (.efi.signed) and UKI signed by sbctl, keys backed up to /home/sbctl-keys-backup
# Printer:    CUPS (cups.socket), paper A4 from LC_PAPER, Brother DCP-L2600D driver + brscan5 scanner driver built from own PKGBUILDs

set -euo pipefail

# --- CONFIG ---

KEEP_HOME="no"
KEYMAP="us"
CONSOLE_FONT="ter-232b"
TARGET_DISK="/dev/disk/by-id/nvme-Samsung_SSD_970_PRO_512GB_SERIAL"
ESP_SIZE="1G"
ROOT_SIZE="100G"
KERNEL_PARAMS="rw zswap.enabled=0"
TIMEZONE="Europe/Bratislava"
LOCALE_LANG="en_US.UTF-8"
LOCALE_FORMATS="sk_SK.UTF-8"
HOST_NAME="suggorath-pc"
PRETTY_HOST_NAME="SUGGORATH-PC"
HARDWARE_MODEL="ROG STRIX X670E-F GAMING WIFI"
USER_NAME="suggorath"
USER_FULL_NAME="Suggorath"
PRINTER_NAME="DCP-L2600D"
PRINTER_URI="usb://Brother/DCP-L2600D?serial=E83173H4N371555"
#WIFI_SSID=""
#WIFI_PASSPHRASE=""

# --- LIVE CONSOLE ---

# Set keymap for the live ISO
loadkeys "$KEYMAP"

# Set font for the live ISO
setfont "$CONSOLE_FONT"

# --- CHECKS ---

# Check boot mode
cat /sys/firmware/efi/fw_platform_size

# Check internet connection
ping -c 3 ping.archlinux.org

# Check system clock
timedatectl

# --- ERASE TARGET DISK (new install only) ---

if [[ "$KEEP_HOME" == "no" ]]; then
  # Erase file system signatures
  wipefs -a "$TARGET_DISK"

  # Erase partition table
  sgdisk --zap-all "$TARGET_DISK"
fi

# --- PARTITIONS ---

if [[ "$KEEP_HOME" == "no" ]]; then
  # Create partitions
  sgdisk -I \
    -n 1:0:+"$ESP_SIZE"  -t 1:ef00 -c 1:ARCH_ESP \
    -n 2:0:+"$ROOT_SIZE" -t 2:8304 -c 2:ARCH_ROOT \
    -n 3:0:0             -t 3:8302 -c 3:ARCH_HOME \
    "$TARGET_DISK"

  # Reload partition table
  partprobe "$TARGET_DISK"

  # Wait until the new partitions are visible
  udevadm settle
else
  # Check that the existing partitions are there (stops the script if one is missing)
  ls -l /dev/disk/by-partlabel/ARCH_ESP /dev/disk/by-partlabel/ARCH_ROOT /dev/disk/by-partlabel/ARCH_HOME
fi

# --- FILE SYSTEMS ---

# Format ESP
mkfs.fat -F 32 -n ARCH_ESP /dev/disk/by-partlabel/ARCH_ESP

# Format root
mkfs.ext4 -F -L ARCH_ROOT /dev/disk/by-partlabel/ARCH_ROOT

# Format home (new install only, a reinstall keeps it)
if [[ "$KEEP_HOME" == "no" ]]; then
  mkfs.ext4 -F -m 1 -L ARCH_HOME /dev/disk/by-partlabel/ARCH_HOME
fi

# --- MOUNT ---

# Mount root
mount /dev/disk/by-partlabel/ARCH_ROOT /mnt

# Mount ESP
mount --mkdir -o fmask=0177,dmask=0077 /dev/disk/by-partlabel/ARCH_ESP /mnt/efi

# Mount home
mount --mkdir /dev/disk/by-partlabel/ARCH_HOME /mnt/home

# --- UKI SETUP ---

# Set kernel parameters
mkdir -p /mnt/etc/kernel
echo "root=PARTUUID=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/ARCH_ROOT) $KERNEL_PARAMS" > /mnt/etc/kernel/cmdline

# Set kernel parameters in separate files (unused, /etc/kernel/cmdline is used)
#mkdir -p /mnt/etc/cmdline.d
#echo "root=PARTUUID=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/ARCH_ROOT) rw" > /mnt/etc/cmdline.d/10-root.conf
#echo "zswap.enabled=0" > /mnt/etc/cmdline.d/20-swap.conf

# Build only the UKI
mkdir -p /mnt/etc/mkinitcpio.d
cat > /mnt/etc/mkinitcpio.d/linux.preset <<EOF
# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

#default_config="/etc/mkinitcpio.conf"
#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"
#default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
EOF

# --- INSTALL SYSTEM ---

# Install base packages, Linux kernel, firmware and CPU microcode
pacstrap -K /mnt base linux linux-firmware amd-ucode

# --- FSTAB ---

# Generate fstab
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab

# --- TIME ---

# Set time zone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime

# Set hardware clock
arch-chroot -S /mnt hwclock --systohc

# Enable time sync
arch-chroot -S /mnt systemctl enable systemd-timesyncd.service

# --- LOCALIZATION ---

# Select locales
sed -i -e "s/^#$LOCALE_LANG /$LOCALE_LANG /" -e "s/^#$LOCALE_FORMATS /$LOCALE_FORMATS /" /mnt/etc/locale.gen

# Generate locales
arch-chroot -S /mnt locale-gen

# Set locale
cat > /mnt/etc/locale.conf <<EOF
LANG=$LOCALE_LANG
#LANGUAGE=en_US:en
LC_CTYPE=$LOCALE_FORMATS
LC_NUMERIC=$LOCALE_FORMATS
LC_TIME=$LOCALE_FORMATS
LC_COLLATE=$LOCALE_FORMATS
LC_MONETARY=$LOCALE_FORMATS
#LC_MESSAGES=$LOCALE_LANG
LC_PAPER=$LOCALE_FORMATS
LC_NAME=$LOCALE_FORMATS
LC_ADDRESS=$LOCALE_FORMATS
LC_TELEPHONE=$LOCALE_FORMATS
LC_MEASUREMENT=$LOCALE_FORMATS
LC_IDENTIFICATION=$LOCALE_FORMATS
EOF

# --- CONSOLE KEYMAP AND FONT ---

# Install console fonts
arch-chroot -S /mnt pacman -S --noconfirm terminus-font

# Set keymap and font
cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=$KEYMAP
#KEYMAP_TOGGLE=
FONT=$CONSOLE_FONT
#FONT_MAP=8859-2
#FONT_UNIMAP=
#FONT_SCALE=100%
EOF

# --- HOSTNAME ---

# Set hostname
echo "$HOST_NAME" > /mnt/etc/hostname

# Resolve own hostname locally
cat > /mnt/etc/hosts <<EOF
127.0.0.1        localhost
::1              localhost
127.0.1.1        $HOST_NAME
EOF

# Set machine info
cat > /mnt/etc/machine-info <<EOF
PRETTY_HOSTNAME="$PRETTY_HOST_NAME"
#ICON_NAME=computer-desktop
#CHASSIS=desktop
#DEPLOYMENT=
#LOCATION=
#TAGS=
#HARDWARE_VENDOR=
HARDWARE_MODEL="$HARDWARE_MODEL"
#HARDWARE_SKU=
#HARDWARE_VERSION=
EOF

# --- NETWORK ---

# Install NetworkManager
arch-chroot -S /mnt pacman -S --noconfirm networkmanager

# Enable NetworkManager
arch-chroot -S /mnt systemctl enable NetworkManager.service

# Enable DNS resolver
arch-chroot -S /mnt systemctl enable systemd-resolved.service

# Use DNS resolver for all programs
ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# Use own encrypted DNS servers instead of the router (unused, DNS comes from the router)
#mkdir -p /mnt/etc/systemd/resolved.conf.d
#cat > /mnt/etc/systemd/resolved.conf.d/60-dns.conf <<EOF
#[Resolve]
#DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
#DNSOverTLS=yes
#Domains=~.
#EOF

# --- FIREWALL ---

# Install firewalld (default zone public: only ssh and dhcpv6-client allowed in)
arch-chroot -S /mnt pacman -S --noconfirm firewalld

# Enable firewalld
arch-chroot -S /mnt systemctl enable firewalld.service

# --- ROOT PASSWORD ---

# Set root password (typed twice, not stored in the script)
arch-chroot -S /mnt passwd

# --- USER ---

# Install sudo
arch-chroot -S /mnt pacman -S --noconfirm sudo

# Create user with own group, home directory, admin group wheel and bash
# (reinstall: the home directory already exists, the first user gets UID 1000 again, so the files stay owned)
if [[ "$KEEP_HOME" == "no" ]]; then
  arch-chroot -S /mnt useradd -m -G wheel -c "$USER_FULL_NAME" -s /bin/bash "$USER_NAME"
else
  arch-chroot -S /mnt useradd -M -G wheel -c "$USER_FULL_NAME" -s /bin/bash "$USER_NAME"
fi

# Set user password (typed twice, not stored in the script)
arch-chroot -S /mnt passwd "$USER_NAME"

# Allow members of wheel to run any command as root
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel

# Check sudo configuration
arch-chroot -S /mnt visudo -c

# --- EXTRA PACKAGES ---

# Install FAT32 tools (check of the ESP at boot)
arch-chroot -S /mnt pacman -S --noconfirm dosfstools

# Install text editor
arch-chroot -S /mnt pacman -S --noconfirm nano

# Install manual pages and pager
arch-chroot -S /mnt pacman -S --noconfirm man-db man-pages less

# Install command completion for bash
arch-chroot -S /mnt pacman -S --noconfirm bash-completion

# Install pacman tools (paccache, checkupdates, pactree, pacdiff)
arch-chroot -S /mnt pacman -S --noconfirm pacman-contrib

# Clean old packages from the pacman cache every week (keeps the last 3 versions)
arch-chroot -S /mnt systemctl enable paccache.timer

# --- SSD ---

# Trim the SSD every week
arch-chroot -S /mnt systemctl enable fstrim.timer

# --- SWAP ---

# Install zram swap
arch-chroot -S /mnt pacman -S --noconfirm zram-generator

# Set zram swap (compressed swap in RAM)
cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# Tune memory management for swap in RAM
cat > /mnt/etc/sysctl.d/99-vm-zram-parameters.conf <<EOF
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF

# --- SLEEP ---

# Disable suspend and hibernation (NVIDIA suspend is not set up, no disk swap for hibernation)
mkdir -p /mnt/etc/systemd/sleep.conf.d
cat > /mnt/etc/systemd/sleep.conf.d/disable-sleep.conf <<EOF
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
EOF

# --- NVIDIA ---

# Enable the multilib repository (32-bit libraries for Steam and Wine)
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /mnt/etc/pacman.conf

# Install NVIDIA driver, 32-bit libraries, video decoding (VA-API) and settings
arch-chroot -S /mnt pacman -Syu --noconfirm nvidia-open lib32-nvidia-utils libva-nvidia-driver nvidia-settings

# Load the NVIDIA driver early from the UKI, without the kms hook (keeps nouveau out)
mkdir -p /mnt/etc/mkinitcpio.conf.d
cat > /mnt/etc/mkinitcpio.conf.d/nvidia.conf <<EOF
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block filesystems fsck)
EOF

# --- SOUND ---

# Install sound server, session manager and support for PulseAudio, ALSA, JACK and 32-bit programs
arch-chroot -S /mnt pacman -S --noconfirm pipewire wireplumber pipewire-audio pipewire-pulse pipewire-alsa pipewire-jack lib32-pipewire

# Install ALSA tools (alsamixer, aplay, speaker-test) and saving of the mixer state
arch-chroot -S /mnt pacman -S --noconfirm alsa-utils

# --- BLUETOOTH ---

# Install Bluetooth stack, bluetoothctl and file transfer
arch-chroot -S /mnt pacman -S --noconfirm bluez bluez-utils bluez-obex

# Enable Bluetooth
arch-chroot -S /mnt systemctl enable bluetooth.service

# --- PRINTER AND SCANNER ---

# Install print system, scanner access, tools needed by the Brother drivers and the package build tool
arch-chroot -S /mnt pacman -S --noconfirm cups ghostscript perl which sane fakeroot

# Start the print system when a program prints
arch-chroot -S /mnt systemctl enable cups.socket

# Write package recipe for the Brother printer driver
mkdir -p "/mnt/home/$USER_NAME/pkgbuilds/brother-dcp-l2600d"
cat > "/mnt/home/$USER_NAME/pkgbuilds/brother-dcp-l2600d/PKGBUILD" <<'EOF'
# Brother DCP-L2600D printer driver (LPR + CUPS wrapper from Brother, 64-bit part only)
pkgname=brother-dcp-l2600d
pkgver=4.1.0
pkgrel=2
pkgdesc="LPR and CUPS driver for the Brother DCP-L2600D printer"
arch=('x86_64')
url="https://support.brother.com/g/b/downloadlist.aspx?c=eu_ot&lang=en&prod=dcpl2600d_eu_as&os=127"
license=('custom:Brother')
depends=('cups' 'ghostscript' 'perl' 'which')
options=('!strip' '!debug')
source=("https://download.brother.com/welcome/dlf106007/dcpl2600dpdrv-4.1.0-2.i386.rpm")
sha256sums=('24e4630dbb1af041689efa2093befeb2fb46537430285b80afde48a8405ceb9c')

package() {
  local src="$srcdir/opt/brother/Printers/DCPL2600D"
  local dst="$pkgdir/opt/brother/Printers/DCPL2600D"

  # Driver files stay in /opt (the filter finds its files from its own path)
  install -d "$dst/lpd"
  cp -r "$src/cupswrapper" "$src/inf" "$dst/"
  install -m755 "$src/lpd/lpdfilter" "$src/lpd/x86_64/rawtobr3" "$src/lpd/x86_64/brprintconflsr3" "$dst/lpd/"

  # Printer description for CUPS
  install -Dm644 "$src/cupswrapper/brother-DCPL2600D-cups-en.ppd" \
    "$pkgdir/usr/share/cups/model/Brother/brother-DCPL2600D-cups-en.ppd"

  # CUPS filter named in the PPD
  install -d "$pkgdir/usr/lib/cups/filter"
  ln -s /opt/brother/Printers/DCPL2600D/cupswrapper/lpdwrapper \
    "$pkgdir/usr/lib/cups/filter/brother_lpdwrapper_DCPL2600D"

  install -Dm644 "$src/LICENSE_ENG.txt" "$pkgdir/usr/share/licenses/$pkgname/LICENSE_ENG.txt"
}
EOF

# Write package recipe for the Brother scanner driver
mkdir -p "/mnt/home/$USER_NAME/pkgbuilds/brscan5"
cat > "/mnt/home/$USER_NAME/pkgbuilds/brscan5/PKGBUILD" <<'EOF'
# Brother SANE scanner driver (based on the AUR brscan5 PKGBUILD)
pkgname=brscan5
pkgver=1.8.1
pkgrel=1
pkgdesc="SANE driver from Brother for compatible models"
arch=('x86_64')
url="https://support.brother.com/g/b/downloadlist.aspx?c=eu_ot&lang=en&prod=dcpl2600d_eu_as&os=127"
license=('GPL-2.0-only' 'custom:Brother')
depends=('sane' 'libusb' 'avahi' 'gcc-libs' 'systemd-libs')
optdepends=('gtk2: for brscan_gnetconfig')
options=('!strip' '!debug')
source=("https://download.brother.com/welcome/dlf104036/brscan5-1.8.1-0.x86_64.rpm")
sha256sums=('a085e529e2193f050f489639c70e19f52afdec7252b2ac5240eaaddec4febdf7')

package() {
  local dir="$pkgdir/opt/brother/scanner/brscan5"

  cp -r "$srcdir/etc" "$srcdir/opt" "$pkgdir/"

  # Load the Brother backend in SANE
  install -d "$pkgdir/etc/sane.d/dll.d"
  echo "brother5" > "$pkgdir/etc/sane.d/dll.d/brother5.conf"

  # Mark Brother scanners for SANE, so the logged-in user gets access (uaccess)
  install -Dm644 "$dir/udev-rules/NN-brother-mfp-brscan5-1.0.2-2.rules" "$pkgdir/usr/lib/udev/rules.d/40-brscan5.rules"
  sed -i '/SYSFS/d' "$pkgdir/usr/lib/udev/rules.d/40-brscan5.rules"

  # SANE backend
  install -d "$pkgdir/usr/lib/sane"
  mv "$dir/libsane-brother5.so.1.0.7" "$pkgdir/usr/lib/sane/"
  ln -s libsane-brother5.so.1.0.7 "$pkgdir/usr/lib/sane/libsane-brother5.so.1"
  ln -s libsane-brother5.so.1 "$pkgdir/usr/lib/sane/libsane-brother5.so"

  # Libraries used by the backend
  mv "$dir/libLxBsScanCoreApi.so.3.2.6" "$pkgdir/usr/lib/"
  ln -s libLxBsScanCoreApi.so.3.2.6 "$pkgdir/usr/lib/libLxBsScanCoreApi.so.3"
  ln -s libLxBsScanCoreApi.so.3 "$pkgdir/usr/lib/libLxBsScanCoreApi.so"
  local lib
  for lib in libLxBsNetDevAccs libLxBsDeviceAccs libLxBsUsbDevAccs; do
    mv "$dir/$lib.so.1.0.0" "$pkgdir/usr/lib/"
    ln -s "$lib.so.1.0.0" "$pkgdir/usr/lib/$lib.so.1"
    ln -s "$lib.so.1" "$pkgdir/usr/lib/$lib.so"
  done

  # Tools in /usr/bin, links left in /opt
  install -d "$pkgdir/usr/bin"
  local bin
  for bin in brsaneconfig5 brscan_cnetconfig brscan_gnetconfig setupSaneScan5; do
    mv "$dir/$bin" "$pkgdir/usr/bin/"
    ln -s "/usr/bin/$bin" "$dir/$bin"
  done

  install -Dm644 "$dir/doc/LICENSE_ENG.txt" "$pkgdir/usr/share/licenses/$pkgname/LICENSE_ENG.txt"
}
EOF

# Give the recipes to the user (makepkg does not run as root)
arch-chroot -S /mnt chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/pkgbuilds"

# Build the Brother driver packages (-f: build again even if a package from an earlier install is there)
arch-chroot -S -u "$USER_NAME" /mnt makepkg -f --dir "/home/$USER_NAME/pkgbuilds/brother-dcp-l2600d"
arch-chroot -S -u "$USER_NAME" /mnt makepkg -f --dir "/home/$USER_NAME/pkgbuilds/brscan5"

# Install the Brother driver packages
arch-chroot -S /mnt pacman -U --noconfirm \
  "/home/$USER_NAME/pkgbuilds/brother-dcp-l2600d/brother-dcp-l2600d-4.1.0-2-x86_64.pkg.tar.zst" \
  "/home/$USER_NAME/pkgbuilds/brscan5/brscan5-1.8.1-1-x86_64.pkg.tar.zst"

# Add the printer to CUPS as the default printer (CUPS runs only for this command)
arch-chroot -S /mnt bash -c '
  cupsd -f &
  until [ -S /run/cups/cups.sock ]; do sleep 0.5; done
  lpadmin -p "$1" -E -v "$2" -m Brother/brother-DCPL2600D-cups-en.ppd -D "Brother DCP-L2600D" -o printer-is-shared=false
  lpadmin -d "$1"
  kill $!
  wait
' _ "$PRINTER_NAME" "$PRINTER_URI"

# --- DESKTOP (KDE PLASMA) ---

# Install the fonts and name the providers pacman would otherwise pick itself
# (OCR languages for Spectacle and Skanpage: Slovak + English, not the first in the list)
arch-chroot -S /mnt pacman -S --noconfirm noto-fonts noto-fonts-emoji qt6-multimedia-ffmpeg \
  tesseract-data-slk tesseract-data-eng

# Install Plasma (plasma-desktop pulls the core, the rest chosen in plasma_packages.md)
arch-chroot -S /mnt pacman -S --noconfirm plasma-desktop kscreen kinfocenter kwallet-pam \
  breeze-gtk kde-gtk-config plasma-nm plasma-pa bluedevil print-manager plasma-firewall \
  spectacle plasma-systemmonitor plasma-login-manager

# Install the applications (terminal, files, archives, calculator, images, scanner, browser)
arch-chroot -S /mnt pacman -S --noconfirm konsole dolphin ark 7zip unrar kcalc gwenview \
  skanpage firefox

# Set the graphical keyboard layouts US + Slovak QWERTY, Alt+Shift switches (also on the login screen)
mkdir -p /mnt/etc/X11/xorg.conf.d
cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "us,sk"
        Option "XkbVariant" ",qwerty"
        Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF

# Start the Plasma login screen at boot
arch-chroot -S /mnt systemctl enable plasmalogin.service

# --- CONTAINERS AND EDITOR ---

# Install Podman (rootless containers), its runtime crun and podman-compose (runs compose.yaml files)
arch-chroot -S /mnt pacman -S --noconfirm podman crun podman-compose

# Search Docker Hub for short image names (e.g. "postgres" in compose files)
mkdir -p /mnt/etc/containers/registries.conf.d
cat > /mnt/etc/containers/registries.conf.d/10-unqualified-search-registries.conf <<EOF
unqualified-search-registries = ["docker.io"]
EOF

# Install the Zed editor (netcat named so pacman does not have to choose one)
arch-chroot -S /mnt pacman -S --noconfirm zed openbsd-netcat

# Let Zed use Podman for dev containers (only if the user has no Zed settings yet)
if [[ ! -f "/mnt/home/$USER_NAME/.config/zed/settings.json" ]]; then
  mkdir -p "/mnt/home/$USER_NAME/.config/zed"
  cat > "/mnt/home/$USER_NAME/.config/zed/settings.json" <<EOF
{
  "use_podman": true
}
EOF
  arch-chroot -S /mnt chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"
fi

# --- SECURE BOOT ---

# Install Secure Boot key manager (also signs files on every update)
arch-chroot -S /mnt pacman -S --noconfirm sbctl

if [[ "$KEEP_HOME" == "no" ]]; then
  # Create own Secure Boot keys (PK, KEK, db)
  arch-chroot -S /mnt sbctl create-keys
else
  # Restore the Secure Boot keys of the first install (they are already in the firmware)
  cp -a /mnt/home/sbctl-keys-backup /mnt/var/lib/sbctl
fi

# Sign the boot loader before it is copied to the ESP (bootctl prefers the .efi.signed file)
arch-chroot -S /mnt sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi

# --- BOOT LOADER ---

# Install systemd-boot to the ESP (no UEFI boot entry)
arch-chroot -S /mnt bootctl install --no-variables

# Set boot menu
cat > /mnt/efi/loader/loader.conf <<EOF
# Default entry {first entry} [entry id e.g. arch-linux.efi, glob pattern, @saved]
default                          arch-linux.efi

# Menu timeout in seconds {0} [seconds, 0, menu-hidden, menu-disabled, menu-force]
timeout                          0

# Menu resolution {keep} [0, 1, 2, auto, max, keep]
#console-mode                    keep

# Editing kernel parameters in the menu {yes} [yes, no]
editor                           no

# Automatic entries found on the ESP {yes} [yes, no]
#auto-entries                    yes

# "Reboot Into Firmware Interface" entry {yes} [yes, no]
#auto-firmware                   yes

# "Reboot The System" entry {no} [yes, no]
#auto-reboot                     no

# "Power Off The System" entry {no} [yes, no]
#auto-poweroff                   no

# Beep in the menu {no} [yes, no]
#beep                            no

# Secure Boot key enrollment from the ESP {if-safe} [if-safe, manual, off, force]
#secure-boot-enroll              if-safe

# Action after key enrollment {reboot} [reboot, shutdown]
#secure-boot-enroll-action       reboot

# Warning before key enrollment in seconds {15} [seconds, 0, hidden]
#secure-boot-enroll-timeout-sec  15

# BitLocker workaround {no} [yes, no]
#reboot-for-bitlocker            no

# Reboot if the entry fails to start {auto} [yes, no, auto]
#reboot-on-error                 auto

# systemd-boot log level {info} [emerg, alert, crit, err, warning, notice, info, debug]
#log-level                       info
EOF

# Add "Arch Linux" to the firmware boot menu (F8), Windows stays first in the boot order
# (reinstall: the entry from the first install still points to the same ESP partition)
if [[ "$KEEP_HOME" == "no" ]]; then
  efibootmgr --create-only --disk "$TARGET_DISK" --part 1 --label "Arch Linux" --loader '\EFI\systemd\systemd-bootx64.efi'
fi

# --- WI-FI (only without the Ethernet cable) ---

# Save Wi-Fi network
#cat > "/mnt/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection" <<EOF
#[connection]
#id=$WIFI_SSID
#type=wifi
#autoconnect=true
#
#[wifi]
#mode=infrastructure
#ssid=$WIFI_SSID
#
#[wifi-security]
#key-mgmt=wpa-psk
#psk=$WIFI_PASSPHRASE
#
#[ipv4]
#method=auto
#
#[ipv6]
#method=auto
#EOF

# Allow only root to read the Wi-Fi network
#chmod 600 "/mnt/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection"

# --- UKI ---

# Rebuild the UKI with the final settings (keymap, font), sbctl signs it
arch-chroot -S /mnt mkinitcpio -P

# --- SECURE BOOT KEYS ---

# Check that every boot file on the ESP is signed
arch-chroot -S /mnt sbctl verify

if [[ "$KEEP_HOME" == "no" ]]; then
  # Back up the Secure Boot keys to /home (only root can read them)
  cp -a /mnt/var/lib/sbctl "/mnt/home/sbctl-keys-backup"
  chmod 700 "/mnt/home/sbctl-keys-backup"

  # Write own keys + Microsoft and ASUS keys into the firmware (firmware must be in Setup Mode)
  arch-chroot -S /mnt sbctl enroll-keys --microsoft --firmware-builtin
fi
