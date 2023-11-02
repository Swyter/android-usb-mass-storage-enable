#!/bin/sh

# https://github.com/SoulForeverInPeace/Boot-PC/blob/12924535c2a469a930cd2fbb4763b1578a022727/app/src/main/kotlin/com/my/mdmd/MainscreenFragment.kt#L176

# ---
# swy: https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html
#      https://www.kernel.org/doc/html/latest/usb/mass-storage.html
#      http://www.linux-usb.org/gadget/file_storage.html

#  `mount | grep configfs` to get the mount point/path for the virtual config filesystem

# swy: usually mounted at /config
CONFIGFS=`mount -t configfs | head -n1 | cut -d' ' -f 3`

mkdir $CONFIGFS/usb_gadget/swy # swy: create a new gadget
cd    $CONFIGFS/usb_gadget/swy # swy: enter the folder

echo 0x1337 > idVendor  # swy: set the USB manufacturer code
echo 0x1337 > idProduct # swy: set the USB device code

mkdir strings/0x409 # swy: create a folder to store the text descriptors that will be shown to the host; fill it out
echo "1337"     > strings/0x409/serialnumber
echo "Mariposa" > strings/0x409/manufacturer
echo "Cosa"     > strings/0x409/product

mkdir configs/swyconfig.1 # swy: create an empty configuration; the name doesn't matter
mkdir configs/swyconfig.1/strings/0x409
echo "probando mass_storage" > configs/swyconfig.1/strings/0x409/configuration

mkdir functions/mass_storage.0 # swy: create a gadget function of type 'mass_storage', only the part after the . is customizable

# swy: the mass storage driver is aware of the underlying data, so only a well-formatted ISO will work in cdrom mode,
#      and only a partitioned hard drive image will show up otherwise.
#      if the drive appears blank/0 bytes there's your problem.
echo "y"                                   > functions/mass_storage.0/lun.0/ro
echo "y"                                   > functions/mass_storage.0/lun.0/removable
echo "y"                                   > functions/mass_storage.0/lun.0/cdrom
echo "/sdcard/Download/netboot.xyz.iso"    > functions/mass_storage.0/lun.0/file # swy: make sure we assign the actual path last, or setting ro/cdrom won't work until we empty this

ln -s functions/mass_storage.0 configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder

# swy: enable/attach the gadget to the physical USB controller; mark this gadget as active
getprop sys.usb.controller > UDC
setprop sys.usb.state mass_storage

echo "[i] press any key to exit the mass storage gadget mode..." && read
echo 

# swy: dettach the gadget
echo "" > UDC

rm    configs/swyconfig.1/mass_storage.0 #swy: remove the symbolic link to the function
rmdir configs/swyconfig.1/strings/0x409  #swy: deallocate the configuration strings
rmdir configs/swyconfig.1/               #swy: now we can remove the empty config

rmdir functions/mass_storage.0           #swy: remove the now-unlinked function

rmdir strings/0x409                      #swy: deallocate the gadget strings
cd .. && rmdir swy                       #swy: remove the now-empty gadget