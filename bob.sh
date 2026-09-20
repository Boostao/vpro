# Need root to grant session-QEMU access to the USB stick device node.
set -e
DEV=""
# Resolve current node for 090c:3350
for d in /sys/bus/usb/devices/*; do
  [[ -f $d/idVendor && -f $d/idProduct ]] || continue
  v=$(cat "$d/idVendor"); p=$(cat "$d/idProduct")
  if [[ $v == 090c && $p == 3350 ]]; then
    bus=$(printf '%03d' "$(cat "$d/busnum")")
    dev=$(printf '%03d' "$(cat "$d/devnum")")
    DEV="/dev/bus/usb/$bus/$dev"
    break
  fi
done
echo "DEV=$DEV"
[[ -n "$DEV" && -e "$DEV" ]]

# Prefer ACL + durable udev rule
sudo setfacl -m u:bruno:rw "$DEV"
sudo tee /etc/udev/rules.d/70-libvirt-usb-stick.rules >/dev/null <<'EOF'
# Allow user-session libvirt/QEMU to passthrough SMI USB DISK (090c:3350)
SUBSYSTEM=="usb", ATTR{idVendor}=="090c", ATTR{idProduct}=="3350", MODE="0660", OWNER="bruno", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --action=change
sleep 1

# Re-resolve after udev
for d in /sys/bus/usb/devices/*; do
  [[ -f $d/idVendor && -f $d/idProduct ]] || continue
  v=$(cat "$d/idVendor"); p=$(cat "$d/idProduct")
  if [[ $v == 090c && $p == 3350 ]]; then
    bus=$(printf '%03d' "$(cat "$d/busnum")")
    dev=$(printf '%03d' "$(cat "$d/devnum")")
    DEV="/dev/bus/usb/$bus/$dev"
    break
  fi
done
echo "DEV after udev=$DEV"
ls -la "$DEV"
getfacl "$DEV" | head -20
python3 - <<PY
import os
path="$DEV"
fd=os.open(path, os.O_RDWR); os.close(fd); print('RDWR OK')
PY

# Ensure not mounted on host
if findmnt /dev/sda1 >/dev/null 2>&1; then
  udisksctl unmount -b /dev/sda1 || sudo umount /dev/sda1 || true
fi

HOSTDEV_XML=/tmp/win11-usb-stick.xml
cat > "$HOSTDEV_XML" <<'EOF'
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x090c'/>
    <product id='0x3350'/>
  </source>
</hostdev>
EOF

# If a stale config-only hostdev exists, live attach now
virsh attach-device win11 "$HOSTDEV_XML" --live
echo 'LIVE attach OK'
# ensure config still present (idempotent-ish: detach config then attach if duplicate risk)
# Check count of hostdevs
COUNT=$(virsh dumpxml win11 | rg -c "<hostdev" || true)
echo "hostdev count in live xml: $COUNT"
if [[ "${COUNT:-0}" -gt 1 ]]; then
  echo 'multiple hostdevs detected; leaving as-is for inspection'
fi
virsh dumpxml win11 | rg -A15 'hostdev'
virsh qemu-monitor-command win11 --hmp 'info usb'
echo 'Done. In Windows, check This PC / Disk Management for the new USB volume.'
