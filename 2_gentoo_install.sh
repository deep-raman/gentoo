#!/bin/bash


NAMESERVER="8.8.8.8"
DISKSIZE="64G"
SYSDIRS="boot usr var home"

BUILDNAME="20211121T170545Z"
STG3_TAR="stage3-amd64-openrc-$BUILDNAME.tar.xz"
URL_STG3="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/$BUILDNAME/$STG3_TAR"
URL_ENCODED=$(/bin/echo $URL_STG3 | python -c "import urllib.parse;print (urllib.parse.quote(input()))")

read -p "Please enter the ip to assign : " IPADDRESS
read -p "Please provide the broadcast : " BROADCAST
read -p "Please provide the netmask : " NETMASK
read -p "Please provide the gateway : " GATEWAY
read -p "Please provide the hostname: " HOSTNAME

if [[ -z "$IPADDRESS" || -z "$BROADCAST" || -z "$NETMASK" || -z "$GATEWAY" ]]; then
	/bin/echo "ERROR: Please make sure that ipaddress , broadcast and netmask are provided."
	exit 1
fi

if [[ -z "$HOSTNAME" ]]; then
	/bin/echo "ERROR: Please provide the hostname for the server."
	exit 1
fi

IFACE=$(ls /sys/class/net | grep -v lo)


cd /mnt/gentoo && source /etc/profile

/bin/echo "INFO: Starting synchronization of gentoo repository..."

emerge-webrsync

/bin/echo "INFO: synchronization of gentoo repository finished."

/bin/echo "INFO: Adding mountpoints in /etc/fstab"

cat << EOF >> /etc/fstab
/dev/sda1		/boot		ext4		defaults,noatime		1 2
/dev/sda3		none		swap		sw				0 0
/dev/sda4		/		ext4		noatime				0 1
/dev/sda5		/usr		ext4		noatime				0 1
/dev/sda6		/var		ext4		noatime				0 1
/dev/sda7		/home		ext4		noatime				0 1
EOF

/bin/echo "INFO: Configuring /etc/portage/make.conf"
sed -i 's/^CFLAGS.*/CFLAGS="-march=native -O2 -pipe"/' /etc/portage/make.conf
sed -i 's/^CHOST/d' /etc/portage/make.conf
/bin/echo "CHOST=\"x86_64-pc-linux-gnu\"" >> /etc/portage/make.conf

/bin/echo "INFO: Setting locale in /etc/locale.gen"
/bin/echo "" > /etc/locale.gen
/bin/echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
/bin/echo "C.UTF8 UTF-8" >> /etc/locale.gen

/bin/echo "INFO: Generating locales..."

locale-gen

/bin/echo "INFO: Setting hostname"

/bin/echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname

/bin/echo "INFO: Adding network configuration to /etc/conf.d/net"

cat << EOF >> /etc/conf.d/net
config_${IFACE}="$IPADDRESS netmask $NETMASK"
routes_${IFACE}="default via $GATEWAY"
EOF

/bin/echo "INFO: Accept gentoo license /etc/portage/package.license"

/bin/echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" > /etc/portage/package.license

/bin/echo "INFO: emerge gentoo-sources and linux-firmware..."

emerge gentoo-sources linux-firmware

/bin/echo "INFO: Create kernel source dir to /usr/src/linux"

KERNEL_SRC=$(ls /usr/src)

ln -s /usr/src/${KERNEL_SRC} /usr/src/linux

/bin/echo "INFO: emerge genkernel"

emerge genkernel

/bin/echo "INFO: executing kernel compilation"

genkernel all

/bin/echo "INFO: Installing useful packages"

emerge virtual/ssh app-admin/rsyslog cronie sys-apps/iproute2 sudo sys-boot/grub net-misc/ntp vim

/bin/echo "INFO: Enabling services to start on boot : ssh, syslog and cronie"

rc-update add sshd default

rc-update add rsyslog default

rc-update add cronie default

rc-update add ntp-client default

/bin/echo "INFO: allowing wheel group to sudo in /etc/sudoers"

sed -i '/^# %wheel/%wheel/g' /etc/sudoers

/bin/echo "INFO: Installing grub and creating grub.cfg"

grub-install /dev/sda

grub-mkconfig -o /boot/grub/grub.cfg