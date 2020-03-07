#!/bin/bash

QEMU_KERNEL="kernel-qemu-4.14.79-stretch"

if [ -z "$1" ]; then
  echo "No image supplied"
  exit 1
fi

IMG="$1"
if [ ! -f "${IMG}" ]; then
  echo "Not found image '${IMG}'"
  exit 1
fi

###############################################################################
# run_qemu_install: Execute image via qemu
# Parameters:
# - $1: nom de l'image à monter
###############################################################################
run_image () {

	if [ ! -e "$MY/qemu-rpi-kernel" ]; then
		git clone https://github.com/dhruvvyas90/qemu-rpi-kernel.git "$MY/qemu-rpi-kernel"
	fi
  # Needed to run: sudo apt-get -y install qemu-system-arm

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
run_image $IMG
cleanup_old_run
