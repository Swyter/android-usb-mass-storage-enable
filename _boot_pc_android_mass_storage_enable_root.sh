#!/bin/sh

# https://github.com/SoulForeverInPeace/Boot-PC/blob/12924535c2a469a930cd2fbb4763b1578a022727/app/src/main/kotlin/com/my/mdmd/MainscreenFragment.kt#L176
# ls /config/usb_gadget/g1/functions/
# > mass_storage.0

setprop sys.usb.config cdrom
getprop sys.usb.config
setprop sys.usb.configfs 1

cd /config/usb_gadget/g1
getprop sys.usb.config > configs/b.1/strings/0x409/configuration
for f in configs/b.1/f*; do rm $f; done
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
ln -s /config/usb_gadget/g1/functions/mass_storage.0  /config/usb_gadget/g1/configs/b.1/f1
echo "" > /sys/class/android_usb/android1/f_mass_storage/lun0/file
echo  1 > /sys/class/android_usb/android0/f_mass_storage/lun0/cdrom
echo  1 > /sys/class/android_usb/android0/f_mass_storage/lun0/ro
echo -n "/sdcard/Download/netboot.xyz.iso" > configs/b.1/f1/lun.0/file
getprop sys.usb.controller > /config/usb_gadget/g1/UDC
setprop sys.usb.state cdrom


echo "" > /config/usb_gadget/g1/UDC



# ---
# swy: https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html
#      https://www.kernel.org/doc/html/latest/usb/mass-storage.html
#      http://www.linux-usb.org/gadget/file_storage.html

#  `mount | grep configfs` to get the mount point/path for the virtual config filesystem
mkdir /config/usb_gadget/swy
pushd /config/usb_gadget/swy

echo 0x1d6b > idVendor
echo 0x0104 > idProduct

mkdir strings/0x409
echo "1337"     > strings/0x409/serialnumber
echo "Mariposa" > strings/0x409/manufacturer
echo "Cosa"     > strings/0x409/product

mkdir configs/swyconfig.1
mkdir configs/swyconfig.1/strings/0x409
echo "probando mass_storage" > configs/swyconfig.1/strings/0x409/configuration

mkdir functions/mass_storage.0
functions/mass_storage.0/lun.0/file

# swy: the mass storage driver is aware of the underlying data, so only a well-formatted ISO will work in cdrom mode, and a partitioned hard drive image will show up otherwise
#      if the drive appears blank/0 bytes there's your problem
echo "/sdcard/Download/netboot.xyz.iso"    > functions/mass_storage.0/lun.0/file
echo  y                                    > functions/mass_storage.0/lun.0/cdrom
echo  y                                    > functions/mass_storage.0/lun.0/ro
echo  y                                    > functions/mass_storage.0/lun.0/removable

ln -s functions/mass_storage.0 configs/swyconfig.1

# swy: enable/attach the gadget to the physical USB controller
getprop sys.usb.controller > UDC
setprop sys.usb.state mass_storage

# swy: dettach the gadget
echo "" > UDC