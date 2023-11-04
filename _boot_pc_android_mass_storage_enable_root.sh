#!/system/bin/env sh

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


SWY_MOUNT_FILE='/sdcard/Download/netboot.xyz.iso'
SWY_TETHER=0

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
echo "1337"       > strings/0x409/serialnumber
echo "swyter"     > strings/0x409/manufacturer
echo "[andropxe]" > strings/0x409/product

mkdir configs/swyconfig.1 # swy: create an empty configuration; the name doesn't matter
mkdir configs/swyconfig.1/strings/0x409
echo "first rndis, then mass_storage to work on win32" > configs/swyconfig.1/strings/0x409/configuration

# --
if [ $SWY_TETHER ]; then
  # swy: add a RNDIS Windows USB tethering function, here we seem to need the suffix
  mkdir      functions/gsi.rmnet
  mkdir      functions/gsi.dpl
  mkdir      functions/gsi.rndis
  echo "1" > functions/gsi.rndis/rndis_class_id

  ln -s functions/gsi.rmnet configs/swyconfig.1
  ln -s functions/gsi.dpl   configs/swyconfig.1
  ln -s functions/gsi.rndis configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder
fi
# --

mkdir functions/mass_storage.0 # swy: create a gadget function of type 'mass_storage', only the part after the . is customizable

# swy: the mass storage driver is aware of the underlying data, so only a well-formatted ISO will work in cdrom mode,
#      and only a partitioned hard drive image will show up otherwise.
#      if the drive appears blank/0 bytes there's your problem.
echo "y"                                   > functions/mass_storage.0/lun.0/ro
echo "y"                                   > functions/mass_storage.0/lun.0/removable
case "$SWY_MOUNT_FILE" in
*.iso) echo echo "y"                       > functions/mass_storage.0/lun.0/cdrom
*    ) echo echo "n"                       > functions/mass_storage.0/lun.0/cdrom
esac
echo "$SWY_MOUNT_FILE"                     > functions/mass_storage.0/lun.0/file # swy: make sure we assign the actual path last, or setting ro/cdrom won't work until we empty this

ln -s functions/mass_storage.0 configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder


# swy: detach the USB port from the original gadget 
echo "" > ../g1/UDC

# swy: enable/attach the gadget to the physical USB device controller; mark this gadget as active
# swy: note: `getprop sys.usb.controller` == `ls /sys/class/udc`
getprop sys.usb.controller > UDC
setprop sys.usb.state mass_storage

# --
if [ $SWY_TETHER ]; then
  ip address add 10.20.30.1/24 dev rndis0
  ip link set rndis0 up

  # swy: https://github.com/luftreich/android-wired-tether/blob/725e79e9/native/tether/tetherStartStop.cpp#L154
  # swy: these don't seem to work well, networking is broken at both ends
  iptables -F
  iptables -F -t nat
  iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -I FORWARD -s 10.20.30.0/24 -j ACCEPT
  iptables -P FORWARD DROP
  iptables -t nat -I POSTROUTING -s 10.20.30.0/24 -j MASQUERADE

  # swy: these get added by Android, found while diff'ing
  iptables -A tetherctrl_FORWARD -j bw_global_alert
  iptables -A tetherctrl_FORWARD -i wlan0 -o rndis0 -m state --state RELATED,ESTABLISHED -g tetherctrl_counters
  iptables -A tetherctrl_FORWARD -i rndis0 -o wlan0 -m state --state INVALID -j DROP
  iptables -A tetherctrl_FORWARD -i rndis0 -o wlan0 -g tetherctrl_counters

  # swy: --port=0 disables the DNS functionality, we only want it to work as a DHCP server
  #      --enable-tftp --tftp-root="/sdcard/Download" (seemingly no tftp support in the bundled version ¿?)
  #      --conf-file=/data/tmp/dnsmasq.conf
  killall -9 dnsmasq
  dnsmasq --no-daemon --no-hosts --no-resolv --server=8.8.8.8 --interface=rndis0 --dhcp-range=tether,10.20.30.2,10.20.30.20,1h
fi
# --

echo "[i] press any key to exit the mass storage gadget mode..." && read
echo 

# --
if [ $SWY_TETHER ]; then
  # swy: tear down the tables
  iptables -F
  iptables -t nat -F
  iptables -X
  iptables -t nat -X
  iptables -P FORWARD ACCEPT


  killall -9 dnsmasq
  ip link set rndis0 down
  ip address delete 10.20.30.1/32 dev rndis0
fi
# --

# swy: detach the gadget from the physical USB port
echo "" > UDC
echo getprop sys.usb.controller > ../g1/UDC
svc usb setfunctions ""
svc usb resetUsbGadget
svc usb resetUsbPort

rm    configs/swyconfig.1/mass_storage.0 #swy: remove the symbolic link to each function, times two
rm    configs/swyconfig.1/gsi.rndis      #
rmdir configs/swyconfig.1/strings/0x409  #swy: deallocate the configuration strings
rmdir configs/swyconfig.1/               #swy: now we can remove the empty config

rmdir functions/mass_storage.0           #swy: remove the now-unlinked function
if [ $SWY_TETHER ]; then
  rmdir functions/gsi.rmnet              
  rmdir functions/gsi.dpl                
  rmdir functions/gsi.rndis              #swy: remove the now-unlinked function
fi

rmdir strings/0x409                      #swy: deallocate the gadget strings
cd .. && rmdir swy                       #swy: remove the now-empty gadget