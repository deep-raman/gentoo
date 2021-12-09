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

parted /dev/sda mklabel gpt
parted -a optimal /dev/sda mkpart boot 1MiB 64MiB
parted -a optimal /dev/sda mkpart bios_boot 66MiB 70MiB
parted -a optimal /dev/sda mkpart swap 70MiB 4GiB
parted -a optimal /dev/sda mkpart root 4GiB 12GiB
parted -a optimal /dev/sda mkpart usr 12GiB 28GiB
parted -a optimal /dev/sda mkpart var 28GiB 44GiB
parted -a optimal /dev/sda mkpart home 44GiB 100%

parted /dev/sda set 2 bios_grub on

/bin/echo "Disk partitioning completed, please review."

parted /dev/sda print

/bin/echo "Creating filesystems on the partitions."
mkfs.ext4 /dev/sda1
mkswap /dev/sda3
swapon /dev/sda3
mkfs.ext4 /dev/sda4
mkfs.ext4 /dev/sda5
mkfs.ext4 /dev/sda6
mkfs.ext4 /dev/sda7

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

mount /dev/sda4 /mnt/gentoo

/bin/echo "Create system dirs and mount paritions..."

for DIR in $SYSDIRS; do
	mkdir /mnt/gentoo/$DIR
done

mount /dev/sda1 /mnt/gentoo/boot
mount /dev/sda5 /mnt/gentoo/usr
mount /dev/sda6 /mnt/gentoo/var
mount /dev/sda7 /mnt/gentoo/home

/bin/echo "INFO: Paritions mounted successfully."

/bin/echo "Downloading gentoo stage3 files..."

cd /mnt/gentoo && wget $URL_STG3

/bin/echo "Unpack the stage3 files ..."

cd /mnt/gentoo && tar xpf $STG3_TAR

cd /mnt/gentoo && mount -t proc none proc
cd /mnt/gentoo && mount --rbind /sys sys
cd /mnt/gentoo && mount --make-rslave sys
cd /mnt/gentoo && mount --rbind /dev dev
cd /mnt/gentoo && mount --make-rslave dev

cd /mnt/gentoo && cp /etc/resolv.conf etc
