#!/bin/sh

# turn the USB connection of your Android phone into a CD-ROM drive that mounts ISOs and provides tethering two-in-one,
# useful for PXE booting laptops/desktops from the network without needing anything else. requires root privileges.
# --
# created by swyter <swyterzone+usbgadget@gmail.com> in 2023-11-02
# licensed under the MIT license

# based on this: https://github.com/SoulForeverInPeace/Boot-PC/blob/12924535c/app/src/main/kotlin/com/my/mdmd/MainscreenFragment.kt#L176
# --
# swy: https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html
#      https://www.kernel.org/doc/html/latest/usb/mass-storage.html
#      http://www.linux-usb.org/gadget/file_storage.html
#      https://github.com/funshine/uvc-gadget-new/blob/master/doc/src/configfs.md

#  `mount | grep configfs` to get the mount point/path for the virtual config filesystem

# swy: usually mounted at /config
CONFIGFS=`mount -t configfs | head -n1 | cut -d' ' -f 3`

mkdir $CONFIGFS/usb_gadget/swy # swy: create a new gadget
cd    $CONFIGFS/usb_gadget/swy # swy: enter the folder

echo 0x1d6b > idVendor  # swy: set the USB manufacturer code
echo 0x0104 > idProduct # swy: set the USB device code
echo 0x0100 > bcdUSB    # swy: set the USB revision

echo 0xEF > bDeviceClass    # swy: Multi-interface Function: 0xEF
echo    2 > bDeviceSubClass # swy: USB Common Sub Class 2
echo    1 > bDeviceProtocol # swy: USB IAD Protocol 1    
            
mkdir strings/0x409 # swy: create a folder to store the text descriptors that will be shown to the host; fill it out
echo "1337"     > strings/0x409/serialnumber
echo "Mariposa" > strings/0x409/manufacturer
echo "Cosa"     > strings/0x409/product

mkdir configs/swyconfig.1 # swy: create an empty configuration; the name doesn't matter
mkdir configs/swyconfig.1/strings/0x409
echo "first rndis, then mass_storage to work on win32" > configs/swyconfig.1/strings/0x409/configuration

# --

echo 0x1       > os_desc/b_vendor_code 
echo "MSFT100" > os_desc/qw_sign

# swy: add a RNDIS Windows USB tethering function, here we seem to need the suffix
mkdir functions/gsi.rndis
ln -s functions/gsi.rndis configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder

ip address add 192.168.90.1/24 dev rndis0
ip link set rndis0 up

# swy: FIXME: DHCP doesn't work, yet: killall dnsmasq && dnsmasq --no-daemon --interface=rndis0 --listen-address=192.168.90.1 --dhcp-range=192.168.90.5,192.168.90.254 # --conf-file=/data/tmp/dnsmasq.conf

# --

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
# swy: note: `getprop sys.usb.controller` == `ls /sys/class/udc`
getprop sys.usb.controller > UDC
setprop sys.usb.state mass_storage


echo "[i] press any key to exit the mass storage gadget mode..." && read
echo 

killall dnsmasq
ip link set rndis0 down
ip address delete 192.168.90.1/32 dev rndis0

# swy: detach the gadget
echo "" > UDC

rm    configs/swyconfig.1/mass_storage.0 #swy: remove the symbolic link to the function
rm    configs/swyconfig.1/gsi.rndis      #swy: remove the symbolic link to the function
rmdir configs/swyconfig.1/strings/0x409  #swy: deallocate the configuration strings
rmdir configs/swyconfig.1/               #swy: now we can remove the empty config

rmdir functions/mass_storage.0           #swy: remove the now-unlinked function
rmdir functions/gsi.rndis                #swy: remove the now-unlinked function

rmdir strings/0x409                      #swy: deallocate the gadget strings
cd .. && rmdir swy                       #swy: remove the now-empty gadget