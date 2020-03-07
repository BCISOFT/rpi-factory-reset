#!/bin/bash

sudo umount -f -d mnt/restore_boot || true
sudo umount -f -d mnt/restore_rootfs || true
sudo umount -f -d mnt/restore_recovery || true

sudo losetup --detach-all

