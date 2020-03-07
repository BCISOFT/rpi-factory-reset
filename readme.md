Raspberry Pi factory reset
==========================

Scripts used to create raspbian image with factory reset:

1. copy your source image file inside this folder
2. slim down your source with `slim_down_image.sh`
3. insert factory reset partition with `create-factory-reset`
4. optional: shrink image with `shrink` to keep space
5. copy to SD Card with `copy-img.sh` or test with `run_img.sh`

slim_down_image.sh
------------------
Uninstall packages to get a smaller version keeping only bare minimum to restore.

create-factory-reset
--------------------
Insert a new partition for factory reset
Reset with

    sudo /boot/factory_reset --reset

shrink.sh
---------
Reduce partitions size to the maximum. Tested only with raspbian type images:
* 1 dos boot partition
* 1 or 2 linux ext partition(s)

First partition (used for booting) is no modified.

copy-img.sh
-----------
Interactive copy of .img file to SD Card

run-img.sh
----------
Run .img with qemu.
Set `QEMU_KERNEL` to choose kernel.

Need to install:

    - sudo apt-get -y install qemu-system-arm 

cleanup.sh
----------
Cleanup mount and loop device if previous run failed.

References:
-----------
* https://github.com/limepepper/ansible-role-raspberrypi
* https://learn.adafruit.com/resizing-raspberry-pi-boot-partition/bonus-shrinking-images
* https://gist.github.com/hhromic/78e3d849ec239b6a4789ae8842701838
* https://www.epic.dk/2018/08/28/remove-unnecessary-packages-from-raspbian-stretch/
* https://github.com/Drewsif/PiShrink


Example Playbook
----------------

Including an example of how to use your role (for instance, with variables
passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: limepepper.raspberrypi, x: 42 }

License
-------