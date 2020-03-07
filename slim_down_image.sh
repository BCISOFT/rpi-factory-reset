#!/bin/bash

# Source: https://github.com/limepepper/ansible-role-raspberrypi

LANG=en_us_8859_1

# fail on errors, undefined variables, and errors in pipes
#set -eu
#set -o pipefail

###################################""
#set -x
#PS4='Line ${LINENO}: '
###################################"
die () {
    echo >&2 "$@"
    exit 1
}
[ "$#" -eq 1 ] || die "1 argument nécessaire, $# fourni"
BASE=`echo "$1" | rev | cut -f 2- -d '.' | rev`
#BASE=2018-10-09-raspbian-stretch-lite
#BASE=2020-02-13-raspbian-buster-lite

#QEMU_KERNEL="kernel-qemu-4.4.34-jessie"
QEMU_KERNEL="kernel-qemu-4.14.79-stretch"
#QEMU_KERNEL="kernel-qemu-4.19.50-buster"

###############################################################################
# Main entry point
###############################################################################
function main()
{
  pr_header "entering main function"
  #---------------------------------
  
  # paths for base, intermediate and restore images
  IMG_ORIG=${BASE}.img
  [ -f ${IMG_ORIG} ] || { echo "Not found source image '${IMG_ORIG}'" && exit;  }

  IMG_SLIM=${BASE}.slim.img

  pr_header "make a copy of $IMG_ORIG to $IMG_SLIM"
  #------------------------------------------------
  if [ -f "${IMG_SLIM}" ]
  then 
    pr_warn "overwriting slim image file ${IMG_SLIM}"
  fi
  cp -f ${IMG_ORIG} ${IMG_SLIM}
  pr_ok "${IMG_SLIM} created"

  pr_header "Prepare image"
  #-----------------------
  echo "Mounting image ${IMG_SLIM}"
  mount_image $IMG_SLIM

  echo "Create slim_down script"
  sudo cp "$MY/src/slim_down.sh" "$MY/mnt/restore_rootfs/home/pi/slim_down.sh"
  sudo chown 1000:1000 "$MY/mnt/restore_rootfs/home/pi/slim_down.sh"
  sudo chmod +x "$MY/mnt/restore_rootfs/home/pi/slim_down.sh"

  if ! grep -q "slim_down.sh" "$MY/mnt/restore_rootfs/etc/rc.local"; then
    sudo mv "$MY/mnt/restore_rootfs/etc/rc.local" "$MY/mnt/restore_rootfs/etc/rc.local.origin"
    sudo touch "$MY/mnt/restore_rootfs/etc/rc.local"
    sudo chmod +x "$MY/mnt/restore_rootfs/etc/rc.local"
    sudo bash -c "cat > $MY/mnt/restore_rootfs/etc/rc.local" << EOF
#!/bin/sh -e

/home/pi/slim_down.sh
exit 0
EOF
    #sudo sed -i '/exit 0/d' "$MY/mnt/restore_rootfs/etc/rc.local"
    #echo "/home/pi/slim_down.sh" | sudo tee -a "$MY/mnt/restore_rootfs/etc/rc.local"
    #echo "exit 0" | sudo tee -a "$MY/mnt/restore_rootfs/etc/rc.local"
  fi
  sudo touch "$MY/mnt/restore_rootfs/home/pi/DO_SLIMMING"

  echo "Configure apt: do not install additionnal packages"
  sudo bash -c "cat > $MY/mnt/restore_rootfs/etc/apt/apt.conf.d/80noadditional" << EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

  echo "Configure dkpg: do not install documentation in packages"
  sudo bash -c "cat > $MY/mnt/restore_rootfs/etc/dpkg/dpkg.cfg.d/nodoc" << EOF
path-exclude /usr/share/doc/*
path-include /usr/share/doc/*/copyright
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
EOF

  echo "Configure dkpg: do not install locales in packages"
  sudo bash -c "cat > $MY/mnt/restore_rootfs/etc/dpkg/dpkg.cfg.d/nolocale" << EOF
path-exclude /usr/share/locale/*
EOF

  echo "umount image ${IMG_SLIM}"
  umount_image

  pr_ok "${IMG_SLIM} updated"

  pr_header "Execute image and slim"
  #---------------------------------
  run_qemu_install $IMG_SLIM

  pr_ok "Slimming done"

  pr_header "Shrink ${IMG_SLIM}"
  #-----------------------------
  # Source: https://learn.adafruit.com/resizing-raspberry-pi-boot-partition/bonus-shrinking-images

  P_START=$( sudo fdisk -lu $IMG_SLIM | grep Linux | awk '{print $2}' ) # Start of 2nd partition in 512 byte sectors
  P_SIZE=$(( $( sudo fdisk -lu $IMG_SLIM | grep Linux | awk '{print $3}' ) * 1024 )) # Partition size in bytes
  LOOP_DEV=$(sudo losetup -f)
  sudo losetup $LOOP_DEV $IMG_SLIM -o $(($P_START * 512)) --sizelimit $P_SIZE
  sudo fsck -f $LOOP_DEV
  sudo resize2fs -M $LOOP_DEV # Make the filesystem as small as possible
  sudo fsck -f $LOOP_DEV
  P_NEWSIZE=$( sudo dumpe2fs $LOOP_DEV 2>/dev/null | grep '^Block count:' | awk '{print $3}' ) # In 4k blocks
  P_NEWEND=$(( $P_START + ($P_NEWSIZE * 8) + 1 )) # in 512 byte sectors
  sudo losetup -d $LOOP_DEV
  echo -e "p\nd\n2\nn\np\n2\n$P_START\n$P_NEWEND\np\nw\n" | sudo fdisk $IMG_SLIM
  I_SIZE=$((($P_NEWEND + 1) * 512)) # New image size in bytes
  sudo truncate -s $I_SIZE $IMG_SLIM

  pr_ok "Done"

}

###############################################################################
# run_qemu_install: Execute image via qemu
# Parameters:
# - $1: nom de l'image à monter
###############################################################################
run_qemu_install () {

	if [ ! -e "$MY/qemu-rpi-kernel" ]; then
		git clone https://github.com/dhruvvyas90/qemu-rpi-kernel.git "$MY/qemu-rpi-kernel"
	fi
	#sudo apt-get -y install qemu-system-arm

	mount_image $1

	if [ ! -f "$MY/mnt/restore_rootfs/etc/ld.so.preload.bak" ]; then
		sudo mv "$MY/mnt/restore_rootfs/etc/ld.so.preload" "$MY/mnt/restore_rootfs/etc/ld.so.preload.bak"
		sudo touch "$MY/mnt/restore_rootfs/etc/ld.so.preload"
	fi

	# MEMO: Comment out entries containing /dev/mmcblk in /etc/fstab
	# sudo sed -i '/dev\/mmcblk/ s?^?#?' folder_mount/etc/fstab
	
	umount_image

	# First run
  sudo qemu-system-arm -kernel "$MY/qemu-rpi-kernel/$QEMU_KERNEL" -dtb "$MY/qemu-rpi-kernel/versatile-pb.dtb" -cpu arm1176 -m 256 -M versatilepb -serial stdio -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" -drive format=raw,file="$MY/$1" -no-reboot
	# Second run
  #sudo qemu-system-arm -kernel "$MY/qemu-rpi-kernel/$QEMU_KERNEL" -dtb "$MY/qemu-rpi-kernel/versatile-pb.dtb" -cpu arm1176 -m 256 -M versatilepb -serial stdio -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" -drive format=raw,file="$MY/$1" -no-reboot

	mount_image $1

	if [ -f "$MY/mnt/restore_rootfs/etc/ld.so.preload.bak" ]; then
		sudo rm "$MY/mnt/restore_rootfs/etc/ld.so.preload"
		sudo mv "$MY/mnt/restore_rootfs/etc/ld.so.preload.bak" "$MY/mnt/restore_rootfs/etc/ld.so.preload"
	fi

	umount_image
}

###############################################################################
# mount_image $IMG_FILE
# Parameters:
# - $1: nom de l'image à monter
###############################################################################
mount_image () {
	mkdir -p "$MY/mnt/restore_boot" "$MY/mnt/restore_rootfs"
	LOOP_DEV=$(sudo losetup -f)
	# sudo losetup -r -P "$LOOP_DEV" rpi-master.img -> -r = lecture seule
	sudo losetup -P "$LOOP_DEV" "$MY/$1"

	sudo mount "$LOOP_DEV"p1 "$MY/mnt/restore_boot"
  sudo sync; sleep 1
  if [ ! -f "$MY/mnt/restore_boot/kernel.img" ]; then
    pr_alert "mnt/restore_boot not mounted correctly"
    exit 1
  fi

	sudo mount "$LOOP_DEV"p2 "$MY/mnt/restore_rootfs"	
  sudo sync; sleep 1
  if [ ! -f "$MY/mnt/restore_rootfs/etc/hostname" ]; then
    pr_alert "mnt/restore_rootfs not mounted correctly"
    exit 1
  fi
}

###############################################################################
# umount_wait; umount one partition and wait umount successfull
###############################################################################
umount_wait () {
	busy=true
	while $busy
	do
		if mountpoint -q "$1"
	 	then
			sudo umount "$1" 2> /dev/null
			if [ $? -eq 0 ]
			then
				busy=false  # umount successful
			else
				echo -n '.'  # output to show that the script is alive
				sleep 1      # 5 seconds for testing, modify to 300 seconds later on
			fi
		else
			busy=false  # not mounted
		fi
	done
}

###############################################################################
# umount_image: umount $LOOP_DEV partitions
###############################################################################
umount_image () {
	sudo sync
	umount_wait "$MY/mnt/restore_boot"
	umount_wait "$MY/mnt/restore_rootfs"
	sudo losetup -d "$LOOP_DEV"
	pr_ok 'umount done.'
}

###############################################################################
# cleanup_old_run: cleanup mounts in case of previous run failed
###############################################################################
cleanup_old_run() {
  OLD_LOOP=$(mount | grep "mnt/restore_boot" | awk '{print $1}' )||true
  if [ ! -z "$OLD_LOOP" ]; then
  	LOOP_DEV=${OLD_LOOP::-2}
  else
  	LOOP_DEV=
  fi

  umount_wait "$MY/mnt/restore_boot"
  umount_wait "$MY/mnt/restore_rootfs"

  if [ ! -z "$LOOP_DEV" ]; then
  	sudo losetup -d "$LOOP_DEV"
  fi
}

# get current source dir, even if its hidden in links
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  MY="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$MY/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
MY="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source "${MY}/display_funcs"

cleanup_old_run
main

# Sources:
#   https://gist.github.com/hhromic/78e3d849ec239b6a4789ae8842701838
#   https://www.epic.dk/2018/08/28/remove-unnecessary-packages-from-raspbian-stretch/
#   https://github.com/Drewsif/PiShrink

