#!/bin/sh
#-------------------------------------------------------------------
#  ______                         _____
# |  ____|                       / ____|
# | |__     _ __    ___    ___  | (___     ___   _ __    ___    ___
# |  __|   | '__|  / _ \  / _ \  \___ \   / _ \ | '_ \  / __|  / _ \
# | |      | |    |  __/ |  __/  ____) | |  __/ | | | | \__ \ |  __/
# |_|      |_|     \___|  \___| |_____/   \___| |_| |_| |___/  \___|
#-------------------------------------------------------------------
# Extended multi-DE support: KDE Plasma 6, GNOME, XFCE, MATE
##

set -e
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

pkg install -y bsddialog pciutils

# ---------------- GPU detection ----------------
GPU_VENDOR="$(pciconf -lv | awk '/vgapci/{f=1} f&&/vendor/{print; exit}')"

nvidia=0
gpu=""

case "$GPU_VENDOR" in
  *Intel*)
    gpu="INTEL"
    pkg install -y drm-kmod mesa-gallium-va libva-utils libva-intel-media-driver
    sysrc kld_list+="i915kms"
    ;;
  *AMD*)
    gpu="AMD"
    pkg install -y drm-kmod mesa-gallium-va libva-utils
    sysrc kld_list+="amdgpu"
    ;;
  *NVIDIA*)
    gpu="NVIDIA"
    nvidia=1
    pkg install -y nvidia-drm-kmod
    sysrc kld_list+="nvidia-drm"
    echo 'hw.nvidiadrm.modeset=1' >> /boot/loader.conf
    ;;
  *)
    gpu="SCFB"
    pkg install -y xf86-video-scfb
    ;;
esac

# ---------------- base system ----------------
pkg install -y xorg dbus seatd sudo ca_root_nss \
  pipewire wireplumber xdg-utils \
  firefox vlc unzip zip networkmgr

pkg delete -y elogind || true
sysrc dbus_enable=YES
sysrc seatd_enable=YES

# ---------------- Desktop selection ----------------
TMP=$(mktemp)
bsddialog --title "Desktop Environments" \
  --checklist "Select desktop environments:" 25 80 15 \
  kde      "KDE Plasma 6 (Wayland)" off \
  gnome    "GNOME" off \
  xfce     "XFCE" off \
  lxqt     "LXQt" off \
  mate     "MATE" off \
  cinnamon "Cinnamon" off \
  wm       "WindowMaker" off \
  2> "$TMP"

DESKTOPS=$(cat "$TMP")
rm -f "$TMP"
[ -z "$DESKTOPS" ] && exit 0

# ---------------- install desktops ----------------
for de in $DESKTOPS; do
  case "$de" in
    kde)
      pkg install -y plasma6-plasma sddm gwenview okular konsole kcalc ark
      sysrc sddm_enable=YES
      ;;
    gnome)
      pkg install -y gnome gdm
      sysrc gdm_enable=YES
      ;;
    xfce)
      pkg install -y xfce xfce4-goodies lightdm lightdm-gtk-greeter xarchiver shotwell rhythmbox evince-lite thunar
      sysrc lightdm_enable=YES
      ;;
    lxqt)
      pkg install -y lxqt sddm
      sysrc sddm_enable=YES
      ;;
    mate)
      pkg install -y mate mate-session-manager mate-media mate-terminal shotwell rhythmbox brisk-menu cursor-dmz-theme dconf-editor evolution freedesktop-sound-theme
      sysrc lightdm_enable=YES
      ;;
    cinnamon)
      pkg install -y cinnamon cinnamon-session cinnamon-screensaver
      sysrc lightdm_enable=YES
      ;;
    wm)
      pkg install -y windowmaker thunar jpeg-turbo tiff png ImageMagick7 libxml2 libxslt gnutls libffi icu cairo libXft flite libXt portaudio gmake cmake-core openssl freeglut giflib libao xorg-fonts-truetype dbus libxcb xcb-util-cursor xcb-util xcb-util-wm wget gnustep gnustep-back gnustep-base gnustep-gui gnustep-wrapper compton gnustep-make gorm preferences projectcenter terminal.app toolboxkit gmake git lightdm wmdrawer wmmaiload wmdiskmon stalonetray wmcpuload wmnetload wmsystemtray wmix
      sysrc lightdm_enable=YES
      ;;
  esac
done

# ---------------- xinitrc ----------------
XINIT=/usr/share/skel/.xinitrc
for de in $DESKTOPS; do
  case "$de" in
    kde)       echo 'exec dbus-launch --exit-with-session startplasma-wayland' > "$XINIT" ;;
    gnome)     echo 'exec /usr/local/bin/gnome-session' > "$XINIT" ;;
    xfce)      echo 'exec startxfce4' > "$XINIT" ;;
    lxqt)      echo 'exec startlxqt' > "$XINIT" ;;
    mate)      echo 'exec mate-session' > "$XINIT" ;;
    cinnamon)  echo 'exec cinnamon-session' > "$XINIT" ;;
    wm)        echo 'exec wmaker' > "$XINIT" ;;
  esac
done
chmod 755 "$XINIT"

# ==================================================
# PER-DE SYSCTL TUNING
# ==================================================
for de in $DESKTOPS; do
  case "$de" in
    kde)
      echo '# KDE Plasma 6 tuning' >> /etc/sysctl.conf
      echo 'net.local.stream.recvspace=65536' >> /etc/sysctl.conf
      echo 'net.local.stream.sendspace=65536' >> /etc/sysctl.conf
      echo 'kern.ipc.shm_allow_removed=1' >> /etc/sysctl.conf
      ;;
    gnome)
      echo '# GNOME tuning' >> /etc/sysctl.conf
      echo 'kern.ipc.shm_allow_removed=1' >> /etc/sysctl.conf
      echo 'vm.swap_idle_enabled=1' >> /etc/sysctl.conf
      ;;
    xfce|lxqt)
      echo '# Lightweight DE tuning' >> /etc/sysctl.conf
      echo 'vm.swap_idle_enabled=1' >> /etc/sysctl.conf
      ;;
    mate|cinnamon)
      echo "# $de tuning" >> /etc/sysctl.conf
      echo 'vm.swap_idle_enabled=1' >> /etc/sysctl.conf
      ;;
    wm)
      echo "# WindowMaker tuning" >> /etc/sysctl.conf
      ;;
  esac
done

# ==================================================
# Essentials
# ==================================================
pkg install -y firefox vlc xdg-utils networkmgr unzip zip zsh cdrtools bash

# ==================================================
# LAPTOP POWER OPTIMIZATION
# ==================================================
pkg install -y powerdxx
sysrc powerdxx_enable=YES
sysrc powerdxx_flags="-a hiadaptive -b adaptive"

echo 'machdep.hwpstate_pkg_ctrl=1' >> /etc/sysctl.conf
echo 'hw.acpi.cpu.cx_lowest=C3' >> /etc/sysctl.conf
echo 'hw.pci.do_aspm=1' >> /etc/sysctl.conf
echo 'hw.usb.power_save=1' >> /etc/sysctl.conf
echo 'kern.cam.da.default_timeout=30' >> /etc/sysctl.conf
[ "$gpu" = "INTEL" ] && echo 'drm.i915.enable_rc6=7' >> /etc/sysctl.conf
sysrc apm_enable=YES

# ==================================================
# SECURITY + HARDENING
# ==================================================
sysrc kern_securelevel_enable=YES
sysrc kern_securelevel=2
echo 'kern.randompid=1' >> /etc/sysctl.conf
echo 'security.bsd.see_other_uids=0' >> /etc/sysctl.conf
echo 'security.bsd.see_other_gids=0' >> /etc/sysctl.conf

# ---------------- CPU temperature ----------------
echo 'coretemp_load="YES"' >> /boot/loader.conf

# ---------------- procfs ----------------
echo 'proc /proc procfs rw 0 0' >> /etc/fstab

# ==================================================
# COREDUMP CONFIGURATION
# ==================================================
echo 'kern.corefile=/var/coredumps/%U/%N.core' >> /etc/sysctl.conf
mkdir -p /var/coredumps
chmod 777 /var/coredumps
sysctl kern.corefile=/var/coredumps/%U/%N.core
sysctl kern.coredump=1
echo
echo 'You can add this statement in your ~/.login_conf:'
echo ':coredumpsize=0:'

# ==================================================
# CPU MICROCODE
# ==================================================
CPU_VENDOR=$(sysctl -n hw.model | awk '{print $1}')
if echo "$CPU_VENDOR" | grep -iq "AMD"; then
    pkg install -y cpu-microcode-amd
elif echo "$CPU_VENDOR" | grep -iq "Intel"; then
    pkg install -y cpu-microcode-intel
else
    pkg install -y cpu-microcode
fi

# ==================================================
# USER ACCOUNT CONFIGURATION
# ==================================================
# Select users to enable for graphical environment
users=$(pw usershow -a | awk -F":" '$NF != "/usr/sbin/nologin" && $3 > 999 {print $1 " \""$8"\" off"}' | sort)

exec 5>&1
USERS=$(echo ${users} | xargs -o bsddialog --backtitle "FreeBSD Installer" \
	--title "Desktop" --ok-label Add --cancel-label Exit \
	--checklist 'Select the users enabled for the graphical environment:' 0 0 0 2>&1 1>&5)
exec 5>&-

[ $? -ne 0 -o -z "$USERS" ] && exit 0

# Add selected users to operator, video, wheel
for u in $USERS; do
    pw groupmod operator -m "$u"
    pw groupmod video    -m "$u"
    pw groupmod wheel    -m "$u"
done

# ==================================================
# Uncomment sudoers line for wheel
# ==================================================
sed -i '' 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /usr/local/etc/sudoers

# ---------------- cleanup ----------------
pkg autoremove -y
pkg clean -ay

echo
echo "Installation complete."
echo "Reboot required."
