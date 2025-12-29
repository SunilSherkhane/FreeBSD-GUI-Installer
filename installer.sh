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
#

readonly BSDDIALOG_OK=0
readonly BSDDIALOG_YES=$BSDDIALOG_OK
readonly BSDDIALOG_NO=1

readonly XDRIVERFILE=/usr/local/etc/X11/xorg.conf.d/20-installerdriver.conf

### Sanity checks
[ "$(id -u)" -ne 0 ] && exit 1
pkg bootstrap -y
pkg update -f
pkg install -y bsddialog

### SECTION 1: Desktop selection
desktop=$(bsddialog --backtitle "FreeBSD Installer" --title Desktop --colors \
	--menu "Select a desktop environment to install:" 0 0 0 \
	KDE   "KDE Plasma 6 (Wayland)" \
	GNOME "GNOME" \
	XFCE  "XFCE" \
	MATE  "MATE" \
	3>&1 1>&2 2>&3)

[ $? -ne $BSDDIALOG_OK ] && exit 1

if [ -z "$(hostname)" ]; then
	bsddialog --msgbox "Please set a hostname before installing a desktop." 0 0
	exit 1
fi

### SECTION 2: GPU detection (original logic preserved)
PKGGPU=$(fwget -n -q | grep gpu)
BOOTMETHOD=$(sysctl -n machdep.bootmethod)

HELPGPU="\ZbBoot method\Zn: $BOOTMETHOD

\ZbDetected GPU\Zn:
$(pciconf -lv | grep -A4 vga)

\ZbFirmware package\Zn:
$PKGGPU"

gpu=$(bsddialog --backtitle "FreeBSD Installer" --title Desktop \
	--ok-label Install --cancel-label Exit \
	--colors --hmsg "$HELPGPU" --item-depth \
	--radiolist "Select your GPU driver:" 0 0 0 \
	DRM           "Intel / AMD DRM (recommended)" off \
	Intel         "Intel HD3000+ / Sandy Bridge+" off \
	AMD           "AMD HD7000+ / Tahiti+" off \
	Radeon        "Older AMD GPUs" off \
	NVIDIA        "NVIDIA proprietary" off \
	Optimus-Intel "NVIDIA Optimus" off \
	VirtualBox    "VirtualBox guest" off \
	VESA          "Generic VESA (BIOS)" off \
	SCFB          "Generic SCFB (UEFI)" off \
	3>&1 1>&2 2>&3)

[ $? -ne $BSDDIALOG_OK ] && exit 1

### GPU install mapping (unchanged behavior)
toinstall=""
postconfig=""

case "$gpu" in
	DRM|Intel)
		toinstall="drm-kmod mesa-gallium-va libva-utils"
		postconfig='sysrc kld_list+=" i915kms amdgpu"'
		;;
	AMD)
		toinstall="drm-kmod mesa-gallium-va libva-utils"
		postconfig='sysrc kld_list+=" amdgpu"'
		;;
	Radeon)
		toinstall="drm-kmod mesa-gallium-va libva-utils"
		postconfig='sysrc kld_list+=" radeonkms"'
		;;
	VirtualBox)
		toinstall="virtualbox-ose-additions"
		postconfig='sysrc vboxguest_enable=YES vboxservice_enable=YES'
		;;
	VESA)
		toinstall="xf86-video-vesa"
		echo 'Section "Device"
 Identifier "Card0"
 Driver "vesa"
EndSection' > "$XDRIVERFILE"
		;;
	SCFB)
		toinstall="xf86-video-scfb"
		echo 'Section "Device"
 Identifier "Card0"
 Driver "scfb"
EndSection' > "$XDRIVERFILE"
		;;
	NVIDIA|Optimus-Intel)
		toinstall="nvidia-driver"
		postconfig='sysrc kld_list+=" nvidia-modeset"'
		;;
esac

### SECTION 3: Base install
pkg install -y $toinstall xorg dbus hald wireplumber
sysrc dbus_enable=YES
sysrc hald_enable=YES
eval "$postconfig"

### XINITRC defaults
mkdir -p /usr/share/skel

case "$desktop" in
	KDE)
		pkg install -y plasma6 kde-applications sddm
		sysrc sddm_enable=YES
		echo 'exec dbus-launch --exit-with-session ck-launch-session startplasma-wayland 2> error.log' \
			> /usr/share/skel/.xinitrc
		;;
	GNOME)
		pkg install -y gnome gdm
		sysrc gdm_enable=YES
		echo 'exec /usr/local/bin/gnome-session' > /usr/share/skel/.xinitrc
		;;
	XFCE)
		pkg install -y xfce lightdm lightdm-gtk-greeter
		sysrc lightdm_enable=YES
		;;
	MATE)
		pkg install -y mate lightdm lightdm-gtk-greeter
		sysrc lightdm_enable=YES
		;;
esac

### SECTION 4: User configuration (original logic preserved)
users=$(pw usershow -a | awk -F: '$NF!="/usr/sbin/nologin" && $3>999 {print $1 " \""$8"\" off"}')

exec 5>&1
USERS=$(echo $users | xargs -o bsddialog --title "Desktop Users" \
	--checklist "Enable desktop access for:" 0 0 0 2>&1 1>&5)
exec 5>&-

[ -n "$USERS" ] && pw groupmod video -m "$(echo "$USERS" | tr ' ' ',')"

bsddialog --msgbox "Desktop installation complete.\nReboot to start." 10 50
