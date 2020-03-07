#!/bin/bash

# Source: https://learn.adafruit.com/resizing-raspberry-pi-boot-partition/bonus-shrinking-images
LANG=en_us_8859_1

# fail on errors, undefined variables, and errors in pipes
set -eu
set -o pipefail

USER_ID=$(id -u)
if [ "$USER_ID" -ne 0 ]; then
	echo "must run with sudo !"
	exit 1
fi

if (( "$#" != 1 )); then
  echo "Usage: sudo $0 filename"
  exit 1
fi

IMG="$1"
if [[ ! -e $IMG ]]; then
  echo "Usage: sudo $0 filename"
  exit 1
fi


IMG="$1"

NB_PART=$( sudo fdisk -lu $IMG |grep -v Disk|grep "$IMG"|wc -l )
echo "$NB_PART partitions found"
if (( $NB_PART > 3)); then
  echo "Can't shrink image with more than 3 partitions"
  exit 1
fi
if (( $NB_PART == 2 )); then
  echo "shrinking partition #2"
  P_START=$( fdisk -lu $IMG | grep Linux | awk '{print $2}' ) # Start of 2nd partition in 512 byte sectors
  P_SIZE=$(( $( fdisk -lu $IMG | grep Linux | awk '{print $3}' ) * 1024 )) # Partition size in bytes

  LOOP_DEV=$(sudo losetup -f)
  losetup $LOOP_DEV $IMG -o $(($P_START * 512)) --sizelimit $P_SIZE
  fsck -f $LOOP_DEV
  resize2fs -M $LOOP_DEV # Make the filesystem as small as possible
  fsck -f $LOOP_DEV
  P_NEWSIZE=$( dumpe2fs $LOOP_DEV 2>/dev/null | grep '^Block count:' | awk '{print $3}' ) # In 4k blocks
  P_NEWEND=$(( $P_START + ($P_NEWSIZE * 8) + 1 )) # in 512 byte sectors
  losetup -d $LOOP_DEV
  echo -e "p\nd\n2\nn\np\n2\n$P_START\n$P_NEWEND\np\nw\n" | fdisk $IMG
  I_SIZE=$((($P_NEWEND + 1) * 512)) # New image size in bytes
  truncate -s $I_SIZE $IMG

else
  echo "shrinking partition #2"

  PT_ORIG="$(sfdisk -d ${IMG})"
        # label: dos
        # label-id: 0xb995e6c0
        # device: shrink-test.img
        # unit: sectors

        # shrink-test.img1 : start=        8192, size=       87851, type=c
        # shrink-test.img2 : start=       98304, size=     3424256, type=83
        # shrink-test.img3 : start=     3522576, size=     3424256, type=83
  PTABLE_DEVICE=$(echo "${PT_ORIG}" | egrep '^device: ' | cut -d' ' -f2)
        # PTABLE_DEVICE = shrink-test.img

  # fdisk -lu $IMG
        # Disk shrink-test.img: 7.8 GiB, 8388608000 bytes, 16384000 sectors
        # Units: sectors of 1 * 512 = 512 bytes
        # Sector size (logical/physical): 512 bytes / 512 bytes
        # I/O size (minimum/optimal): 512 bytes / 512 bytes
        # Disklabel type: dos
        # Disk identifier: 0xb995e6c0

        # Device           Boot   Start     End Sectors  Size Id Type
        # shrink-test.img1         8192   96042   87851 42.9M  c W95 FAT32 (LBA)
        # shrink-test.img2        98304 3522559 3424256  1.6G 83 Linux
        # shrink-test.img3      3522576 6946831 3424256  1.6G 83 Linux

  P1_START=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}1" | tr -s ' '| cut -d' ' -f4 | tr -d ',')
  P1_SIZE=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}1" | tr -s ' '| cut -d' ' -f6 | tr -d ',')
  P1_END=$(( $P1_START + $P1_SIZE - 1 ))

  P2_START=$( fdisk -lu $IMG | grep ${PTABLE_DEVICE}2 | awk '{print $2}' ) # Start of 2nd partition in 512 byte sectors - P2_START = 98304
  P2_SIZE_LIMIT=$(( $( fdisk -lu $IMG | grep ${PTABLE_DEVICE}2 | awk '{print $3}' ) * 1024 )) # Partition size in bytes - P_SIZE_LIMIT = 7113554944

  # Filesystem check
  LOOP_DEV=$(sudo losetup -f)
  losetup $LOOP_DEV $IMG -o $(($P2_START * 512)) --sizelimit $P2_SIZE_LIMIT
  fsck -f $LOOP_DEV

  # Filesystem resize + 2nd check
  resize2fs -M $LOOP_DEV # Make the filesystem as small as possible
  fsck -f $LOOP_DEV

  P2_NEWSIZE=$( dumpe2fs $LOOP_DEV 2>/dev/null | grep '^Block count:' | awk '{print $3}' ) # In 4k blocks - P_NEWSIZE = 275769
        # memo: 4k / 512 = 8
  P2_NEWEND=$(( $P2_START + ($P2_NEWSIZE * 8) + 1 )) # in 512 byte sectors
        # P_NEWEND = 5728729
  losetup -d $LOOP_DEV


  echo "shrinking partition #3"

  P3_START=$( fdisk -lu $IMG | grep ${PTABLE_DEVICE}3 | awk '{print $2}' ) # Start of 3rd partition in 512 byte sectors
        # P3_START = 3522576
  P3_SIZE_LIMIT=$(( $( fdisk -lu $IMG | grep ${PTABLE_DEVICE}3 | awk '{print $3}' ) * 1024 )) # Partition size in bytes
        # P_SIZE_LIMIT = 7113554944

  # Filesystem check
  LOOP_DEV=$(sudo losetup -f)
  losetup $LOOP_DEV $IMG -o $(($P3_START * 512)) --sizelimit $P3_SIZE_LIMIT
  fsck -f $LOOP_DEV

  # Filesystem resize + 2nd check
  resize2fs -M $LOOP_DEV # Make the filesystem as small as possible
  fsck -f $LOOP_DEV

  P3_NEWSIZE=$( dumpe2fs $LOOP_DEV 2>/dev/null | grep '^Block count:' | awk '{print $3}' ) # In 4k blocks
  P3_NEWEND=$(( $P3_START + ($P3_NEWSIZE * 8) + 1 )) # in 512 byte sectors
  losetup -d $LOOP_DEV

  echo "Review data:"
  echo "============"
  echo ""
  fdisk -lu $IMG
  echo ""
  echo "PT_ORIG       = $PT_ORIG"
  echo ""
  echo "P1_START      = $P1_START"
  echo "P1_SIZE       = $P1_SIZE"
  echo "P1_END        = $P1_END"
  echo ""
  echo "P2_START      = $P2_START"
  echo "P2_SIZE_LIMIT = $P2_SIZE_LIMIT"
  echo "P2_NEWSIZE    = $P2_NEWSIZE"
  echo "P2_NEWEND     = $P2_NEWEND"
  echo ""
  echo "P3_START      = $P3_START"
  echo "P3_SIZE_LIMIT = $P3_SIZE_LIMIT"
  echo "P3_NEWSIZE    = $P3_NEWSIZE"
  echo "P3_NEWEND     = $P3_NEWEND"

  echo "creating new image"

  BASE_NAME=`echo "${PTABLE_DEVICE}" | rev | cut -f 2- -d '.' | rev`
  echo "BASE_NAME = $BASE_NAME"
  TMP_IMG=${BASE_NAME}.shrinked.img

  TMP_P1_START=$P1_START
  TMP_P1_SIZE=$P1_SIZE
  TMP_P1_END=$(( $TMP_P1_START + $TMP_P1_SIZE -1 ))

  TMP_P2_START=$(( ( ( ($TMP_P1_END / 8192) + 1) * 8192)  ))
  TMP_P2_SIZE=$(( ( $P2_NEWSIZE * 8) ))
  TMP_P2_END=$(( $TMP_P2_START + $TMP_P2_SIZE -1 ))

  TMP_P3_START=$(( ( ( ($TMP_P2_END / 8192) + 1) * 8192)  ))
  TMP_P3_SIZE=$(( ( $P3_NEWSIZE * 8) ))
  TMP_P3_END=$(( $TMP_P3_START + $TMP_P3_SIZE -1 ))

  TMP_NEW_I_SIZE=$((($TMP_P3_END + 1) * 512)) # New image size in bytes
  DD_SIZE=$(( ( ($TMP_NEW_I_SIZE/4194304) + 1 ) )) # New image in 4M blocks for dd
  PARTUUID=$(echo "${PT_ORIG}" | egrep '^label-id: ' | cut -d' ' -f2)

  echo ""
  echo "TMP_IMG           = $TMP_IMG"
  echo "PARTUUID          = $PARTUUID"
  echo "PT_ORIG           = $PT_ORIG"
  echo ""
  echo "TMP_P1_START      = $TMP_P1_START"
  echo "TMP_P1_SIZE       = $TMP_P1_SIZE"
  echo "TMP_P1_END        = $TMP_P1_END"
  echo ""
  echo "TMP_P2_START      = $TMP_P2_START"
  echo "TMP_P2_SIZE       = $TMP_P2_SIZE"
  echo "TMP_P2_END        = $TMP_P2_END"
  echo ""
  echo "TMP_P3_START      = $TMP_P3_START"
  echo "TMP_P3_SIZE       = $TMP_P3_SIZE"
  echo "TMP_P3_END        = $TMP_P3_END"
  echo ""
  echo "TMP_NEW_I_SIZE    = $TMP_NEW_I_SIZE"
  echo "DD_SIZE           = $DD_SIZE"

  echo ""
  echo "create a new image $TMP_IMG"

  dd if=/dev/zero bs=4M count=${DD_SIZE} > ${TMP_IMG}
  sync

  sfdisk ${TMP_IMG} <<EOL
label: dos
label-id: ${PARTUUID}
unit: sectors

${TMP_IMG}1 : start=${TMP_P1_START}, size=${TMP_P1_SIZE}, type=c
${TMP_IMG}2 : start=${TMP_P2_START}, size=${TMP_P2_SIZE}, type=83
${TMP_IMG}3 : start=${TMP_P3_START}, size=${TMP_P3_SIZE}, type=83

EOL

  echo ""
  fdisk -lu ${TMP_IMG}
  echo ""

  echo "creating loop devices"
  LOOP_SRC=$(sudo losetup -v  --show -f -P ${IMG})
  sudo partprobe ${LOOP_SRC}
  LOOP_DST=$(sudo losetup -v  --show -f -P ${TMP_IMG})
  sudo partprobe ${LOOP_DST}  

  # echo ""
  # losetup -a
  # blkid
  # echo ""
  # read -p "Press enter to continue ..."

  echo ""
  echo "copying partition 1"
  dd status=progress if=${LOOP_SRC}p1 of=p1 bs=4M
  I_SIZE=$(( $TMP_P1_SIZE * 512)) # New image size in bytes
  truncate -s $I_SIZE p1
  dd status=progress if=p1 of=${LOOP_DST}p1 bs=4M
  rm -f p1

  echo ""
  echo "copying partition 2"
  dd status=progress if=${LOOP_SRC}p2 of=p2 bs=4M
  I_SIZE=$(( $TMP_P2_SIZE * 512)) # New image size in bytes
  truncate -s $I_SIZE p2
  dd status=progress if=p2 of=${LOOP_DST}p2 bs=4M
  rm -f p2

  echo ""
  echo "copying partition 3"
  dd status=progress if=${LOOP_SRC}p3 of=p3 bs=4M
  I_SIZE=$(( $TMP_P3_SIZE * 512)) # New image size in bytes
  truncate -s $I_SIZE p3
  dd status=progress if=p3 of=${LOOP_DST}p3 bs=4M
  rm -f p3

  sync

  echo ""
  echo "deleting loop devices"
  losetup -d $LOOP_SRC
  losetup -d $LOOP_DST

  echo ""
  echo "checking filesystems"
  #TODO read partition table and check only ext4

  LOOP_DST=$(sudo losetup -v  --show -f -P ${TMP_IMG})
  partprobe ${LOOP_DST}
  fsck -f ${LOOP_DST}p2
  fsck -f ${LOOP_DST}p3
  losetup -d $LOOP_DST
  
  # fdisk partition manipulation
  #echo -e "p\nd\n3\nn\np\n3\n$P_START\n$P_NEWEND\np\nw\n" | fdisk $IMG
  #I_SIZE=$((($P_NEWEND + 1) * 512)) # New image size in bytes
  #truncate -s $I_SIZE $IMG

  #########################################################################


  # TODO:
  # - shrink partition 2
  # - shrink partition 3
  # - create new img
  # - calculate start and end of each partitions
  # - fdisk create partitions
  # - dd each partitions
  # - fsck ?
fi



