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


/bin/echo "Configurint interface : $IFACE with $IPADDRESS"
CONFIGURE_IP=$(ifconfig "$IFACE" "$IPADDRESS" broadcast "$BROADCAST" netmask "$NETMASK" up)

/bin/echo "Adding default route via $GATEWAY"

ADD_ROUTE=$(route add default gw  "$GATEWAY")

/bin/echo "Adding nameservers..."

/bin/echo "nameserver $NAMESERVER" >> /etc/resolv.conf

PINGTEST=$(ping google.com -c 1)
if [[ ! -z "PINGTEST" ]]; then
	/bin/echo "OK: Network is configured successfully."
else
	/bin/echo "ERROR: Network configuration failed. Please check..."
	exit 1
fi

/bin/echo "Checking disk size..."

DISK=$(lsblk | grep sda | grep -v sda[1-9] | awk '{print $4}')

if [[ "$DISK" == "$DISKSIZE" ]]; then
	/bin/echo "Disk size check passed, $DISK will be used for the installation."
else
	/bin/echo "Disk check failed, please ensure that disk size is 64GB"
	exit 1
fi

/bin/echo "Creating disk partitions for the installation."
`parted /dev/sda – mklabel gpt`
`parted -a optimal /dev/sda mkpart boot 1MiB 64MiB`
`parted -a optimal /dev/sda mkpart swap 64MiB 4GiB`
`parted -a optimal /dev/sda mkpart root 4GiB 12GiB`
`parted -a optimal /dev/sda mkpart usr 12GiB 28GiB`
`parted -a optimal /dev/sda mkpart var 28GiB 44GiB`
`parted -a optimal /dev/sda mkpart home 44GiB %100`

/bin/echo "Disk partitioning completed, please review."

`parted /dev/sda print`

/bin/echo "Creating filesystems on the partitions."
`mkfs.ext2 /dev/sda1`
`mkswap /dev/sda2`
`swapon /dev/sda2`
`mkfs.ext4 /dev/sda3`
`mkfs.ext4 /dev/sda4`
`mkfs.ext4 /dev/sda5`
`mkfs.ext4 /dev/sda6`

/bin/echo "Check if directory /mnt/gentoo exists"

if [[ -d "/mnt/gentoo" ]]; then
	/bin/echo "OK: directory /mnt/gentoo exists."
else
	/bin/echo "WARNING: directory /mnt/gentoo doesn't exists."
	/bin/echo "INFO: Creating /mnt/gentoo..."
	DIR_CREATE=$(mkdir /mnt/gentoo)
	/bin/echo "OK: /mnt/gentoo created successfully."
fi

/bin/echo "INFO: Mounting /dev/sda3  as root directory on /mnt/gentoo"

`mount /dev/sda3 /mnt/gentoo`

/bin/echo "Create system dirs and mount paritions..."

for DIR in $SYSDIRS; do
	`mkdir /mnt/gentoo/$DIR`
done

`mount /dev/sda1 /mnt/gentoo/boot`
`mount /dev/sda4 /mnt/gentoo/usr`
`mount /dev/sda5 /mnt/gentoo/var`
`mount /dev/sda6 /mnt/gentoo/home`

/bin/echo "INFO: Paritions mounted successfully."

/bin/echo "Downloading gentoo stage3 files..."

`cd /mnt/gentoo && wget $URL_STG3`

/bin/echo "Unpack the stage3 files ..."

`cd /mnt/gentoo && tar xpf $STG3_TAR`

`cd /mnt/gentoo && mount -t proc none proc`
`cd /mnt/gentoo && mount --rbind /sys sys`
`cd /mnt/gentoo && mount --make-rslave sys`
`cd /mnt/gentoo && mount --rbind /dev dev`
`cd /mnt/gentoo && mount --make-rslave dev`

`cd /mnt/gentoo && cp /etc/resolv.conf etc`

`cd /mnt/gentoo && chroot . /bin/bash`

`cd /mnt/gentoo && source /etc/profile`

/bin/echo "INFO: Starting synchronization of gentoo repository..."

`emerge-webrsync`

/bin/echo "INFO: synchronization of gentoo repository finished."

/bin/echo "INFO: Adding mountpoints in /etc/fstab"

cat << EOF >> /etc/fstab
/dev/sda1		/boot		ext2		defaults,noatime		0 2
/dev/sda2		none		swap		sw				0 0
/dev/sda3		/		ext4		noatime				0 1
/dev/sda4		/usr		ext4		noatime				0 1
/dev/sda5		/var		ext4		noatime				0 1
/dev/sda6		/home		ext4		noatime				0 1
EOF

/bin/echo "INFO: Configuring /etc/portage/make.conf"
sed -i 's/^CFLAGS.*/CFLAGS="-march=native -O2 -pipe/' /etc/portage/make.conf
sed -i 's/^CHOST/d' /etc/portage/make.conf
/bin/echo "CHOST=\"x86_64-pc-linux-gnu\"" >> /etc/portage/make.conf

/bin/echo "INFO: Setting locale in /etc/locale.gen"
/bin/echo "" > /etc/locale.gen
/bin/echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
/bin/echo "C.UTF8 UTF-8" >> /etc/locale.gen

/bin/echo "INFO: Generating locales..."

`locale-gen`

/bin/echo "INFO: Setting hostname"

/bin/echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname

/bin/echo "INFO: Adding network configuration to /etc/conf.d/net"

cat << EOF >> /etc/conf.d/net
config_$IFACE="$IPADDRESS netmask $NETMASK"
routes_$IFACE="default via $GATEWAY"
EOF

/bin/echo "INFO: Accept gentoo license /etc/portage/package.license"

/bin/echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" > /etc/portage/package.license

/bin/echo "INFO: emerge gentoo-sources and linux-firmware..."

`emerge gentoo-sources linux-firmware`

/bin/echo "INFO: Create kernel source dir to /usr/src/linux"

KERNEL_SRC=$(ls /usr/src)

`ln -s /usr/src/$KERNEL_SRC /usr/src/linux`

/bin/echo "INFO: emerge genkernel"

emerge genkernel

/bin/echo "INFO: executing kernel compilation"

`genkernel all`

/bin/echo "INFO: Installing useful packages"

`emerge virtual/ssh app-admin/rsyslog cronie sys-apps/iproute2 sudo sys-boot/grub net-misc/ntp vim`

/bin/echo "INFO: Enabling services to start on boot : ssh, syslog and cronie"

`rc-update add sshd default`

`rc-update add rsyslog default`

`rc-update add cronie default`

/bin/echo "INFO: allowing wheel group to sudo in /etc/sudoers"

`sed -i '1s/^#%wheel/%wheel/g' /etc/sudoers`

/bin/echo "INFO: Installing grub and creating grub.cfg"

`grub2-install /dev/sda`

`grub2-mkconfig -o /boot/grub/grub.cfg`
