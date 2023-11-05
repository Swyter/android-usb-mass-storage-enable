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
#  `cat /proc/config.gz | gunzip | grep RNDIS` `cat /proc/config.gz | gunzip | grep CONFIG_USB_F_` to view which gadget functions are built into your running kernel
#  `mount | grep configfs` to get the mount point/path for the virtual config filesystem

# swy: configure your file here, if it's not a plain ISO (i.e. a disk image)
#      change the `cdrom` thing below from 'y' to 'n':
SWY_MOUNT_FILE='/sdcard/Download/netboot.xyz.img'
SWY_MOUNT_CDROM='n'
SWY_MOUNT_READ_ONLY='n'

SWY_TETHER=false # swy: the actual networking on the phone-side doesn't work, yet. don't use this.

printf "[-] creating a USB gadget with mass-storage\n    functionality for your image file:\n    %s (iso: %s)\n" "$SWY_MOUNT_FILE" "$SWY_MOUNT_CDROM"

# --

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
if [ $SWY_TETHER = true ]; then
  # swy: add a RNDIS Windows USB tethering function, here we seem to need the suffix
  mkdir functions/ncm.0  #gsi.rndis
  echo "6e:10:dc:5e:85:cc" > functions/ncm.0/host_addr # swy: https://github.com/RoEdAl/al-net-tools/blob/master/usb-gadget/usb-gadget.sh#L57

  ln -s functions/ncm.0 configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder
fi
# --

mkdir functions/mass_storage.0 # swy: create a gadget function of type 'mass_storage', only the part after the . is customizable

# swy: the mass storage driver is aware of the underlying data, so only a well-formatted ISO will work in cdrom mode,
#      and only a partitioned hard drive image will show up otherwise.
#      if the drive appears blank/0 bytes there's your problem.
echo "$SWY_MOUNT_READ_ONLY"                > functions/mass_storage.0/lun.0/ro
echo "y"                                   > functions/mass_storage.0/lun.0/removable
echo "$SWY_MOUNT_CDROM"                    > functions/mass_storage.0/lun.0/cdrom
#case "$SWY_MOUNT_FILE" in
#*.iso) echo echo "y"                       > functions/mass_storage.0/lun.0/cdrom
#*    ) echo echo "n"                       > functions/mass_storage.0/lun.0/cdrom
#esac
echo "$SWY_MOUNT_FILE"                     > functions/mass_storage.0/lun.0/file # swy: make sure we assign the actual path last, or setting ro/cdrom won't work until we empty this

ln -s functions/mass_storage.0 configs/swyconfig.1 # swy: add a symbolic link to put our function into a premade config folder


# swy: detach the USB port from the original gadget 
echo "" > ../g1/UDC

# swy: enable/attach the gadget to the physical USB device controller; mark this gadget as active
# swy: note: `getprop sys.usb.controller` == `ls /sys/class/udc`
getprop sys.usb.controller > UDC
setprop sys.usb.state mass_storage

# --
if [ $SWY_TETHER = true ]; then # swy: doesn't work, packets don't get through either side (packets show as rx errors in `cat /proc/net/dev`) when the interface is up due to some obscure reason. is it due to the overcomplicated `ip rule` cruft or something else?
  ip address add 192.168.88.1/24 dev usb0
  ip link set usb0 up
  ip route add default via 192.168.2.1 dev wlan0

  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -t nat -F
  iptables -t mangle -F
  iptables -F
  iptables -X
  
  echo 1 > /proc/sys/net/ipv4/ip_forward

  #ip rule add priority 31900 lookup default
  #ip rule add priority 32767 lookup default
  
  #11000:  from all iif lo oif rndis0 uidrange 0-0 lookup local_network
  #17000:  from all iif lo oif rndis0 lookup local_network
  #21000:  from all iif rndis0 lookup wlan0
  
  ip rule add priority 11000  from all iif lo oif usb0 uidrange 0-0 lookup local_network
  ip rule add priority 17000  from all iif lo oif usb0 lookup local_network
  ip rule add priority 21000  from all iif usb0 lookup wlan0
  
  #cat /proc/net/dev

  
  # swy: https://github.com/luftreich/android-wired-tether/blob/725e79e9/native/tether/tetherStartStop.cpp#L154
  # swy: these don't seem to work well, networking is broken at both ends
  iptables -F
  iptables -F -t nat
  iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -I FORWARD -s 192.168.88.0/24 -j ACCEPT
  iptables -P FORWARD DROP
  iptables -t nat -I POSTROUTING -s 192.168.88.0/24 -j MASQUERADE
  
  iptables -I FORWARD -i wlan0 -o usb0 -m state --state RELATED,ESTABLISHED
  iptables -I FORWARD -i usb0 -o wlan0 -m state --state INVALID -j DROP

  # swy: these get added by Android, found while diff'ing
  #iptables -A tetherctrl_FORWARD -j bw_global_alert
  #iptables -A tetherctrl_FORWARD -i wlan0 -o rndis0 -m state --state RELATED,ESTABLISHED -g tetherctrl_counters
  #iptables -A tetherctrl_FORWARD -i rndis0 -o wlan0 -m state --state INVALID -j DROP
  #iptables -A tetherctrl_FORWARD -i rndis0 -o wlan0 -g tetherctrl_counters

  # swy: --port=0 disables the DNS functionality, we only want it to work as a DHCP server
  #      --enable-tftp --tftp-root="/sdcard/Download" (seemingly no tftp support in the bundled version ¿?)
  #      --conf-file=/data/tmp/dnsmasq.conf
  killall -9 dnsmasq
  dnsmasq --no-daemon --no-hosts --no-resolv --server=8.8.8.8 --interface=usb0 --dhcp-range=tether,192.168.88.2,192.168.88.20,1h
fi
# --

echo '[i] mounted; press any key to exit the gadget mode...' && read
echo 

# --
if [ $SWY_TETHER = true ]; then
  # swy: tear down the tables
  iptables -F
  iptables -t nat -F
  iptables -X
  iptables -t nat -X
  iptables -P FORWARD ACCEPT


  killall -9 dnsmasq
  ip link set rndis0 down
  ip address delete 192.168.88.1/32 dev rndis0
fi
# --

# swy: detach the gadget from the physical USB port
echo "" > UDC
setprop sys.usb.state ""
svc usb resetUsbGadget
svc usb resetUsbPort # swy: https://android.stackexchange.com/a/236070
svc usb setFunctions ""

# swy: reattach to the original gadget
getprop sys.usb.controller > ../g1/UDC

rm    configs/swyconfig.1/mass_storage.0 #swy: remove the symbolic link to each function, times two
if [ $SWY_TETHER = true ]; then
  rm  configs/swyconfig.1/ncm.0 #gsi.rndis
fi
rmdir configs/swyconfig.1/strings/0x409  #swy: deallocate the configuration strings
rmdir configs/swyconfig.1/               #swy: now we can remove the empty config

rmdir functions/mass_storage.0           #swy: remove the now-unlinked function
if [ $SWY_TETHER = true ]; then
  rmdir functions/ncm.0 #gsi.rndis
fi

rmdir strings/0x409                      #swy: deallocate the gadget strings
cd .. && rmdir swy                       #swy: remove the now-empty gadget