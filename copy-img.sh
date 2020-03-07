#!/bin/bash

IMG_SRC=""
MY=$(cd `dirname $0` && pwd)

# selection interactive de IMG_SRC
select_source() {
	let i=0
	files=()
	for f in $MY/*.img
	do
		let i=$i+1
		files+=($i "${f#$MY/}")
	done
	RET=$(whiptail --title "Select source" --menu "Please select the source image" 20 80 6 "${files[@]}"  3>&2 2>&1 1>&3)
	if [ $? -eq 0 ]; then # exit with ok
		SEL=$(readlink -f $(ls -1 ./*.img | sed -n "`echo "$RET p" | sed 's/ //'`"))
		# IMG_SRC=$SEL#"$MY/"}
		IMG_SRC=$SEL
	else 
		echo "Cancel"
		exit 1
	fi
}

write_image2sdcard() {
	NB_USB=$(lsblk -p -o NAME,TRAN,TYPE|grep disk|grep mmc|awk '{print $1}' | wc -l)
	if [ $NB_USB -eq 0 ]; then
		echo "Aucune carte SD détectée pour copier l'image. Abandon de la copie."
		exit 1
	fi
	if [ $NB_USB -ne 1 ]; then
		echo "Plusieurs cartes SD connectées. Abandon de la copie."
		exit 1
	fi
	USB_DEVICE=$(lsblk -p -o NAME,TRAN,TYPE|grep disk|grep mmc|awk '{print $1}')
	USB_SIZE=$(lsblk -p|grep disk|grep $USB_DEVICE|awk '{print $4}')
	DEFAULT=--defaultno
	whiptail --yesno "Faut-il copier $IMG_SRC sur $USB_DEVICE ($USB_SIZE)?" $DEFAULT 20 60 2
	RET=$?
	if [ $RET -eq 0 ] ; then
		# oui
		MNT_LIST=$(mount | grep $USB_DEVICE | awk '{print $1}')
		for MNT in $MNT_LIST; do
			echo "umount $MNT"
			sudo umount -f $MNT
		done
		sleep 1
		MNT_LIST=$(mount | grep $USB_DEVICE | awk '{print $1}')
		for MNT in $MNT_LIST; do
			echo "umount $MNT"
			sudo umount -f $MNT
		done
		sleep 1
		echo "gravure de $IMG_SRC sur $USB_DEVICE"
		sudo dd bs=4M if="$IMG_SRC" of="$USB_DEVICE" status=progress conv=fsync
		sudo sync
		MNT_LIST=$(mount | grep $USB_DEVICE | awk '{print $1}')
		for MNT in $MNT_LIST; do
			echo "umount $MNT"
			sudo umount -f $MNT
		done
	elif [ $RET -eq 1 ]; then
		# non
		echo "Copie annulée"
	else
		return $RET
	fi
}

select_source
write_image2sdcard
