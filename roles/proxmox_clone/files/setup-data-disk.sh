#!/bin/bash
# setup-data-disk: format and mount a data disk that proxmox-deploy attached (data_disks). The disk is found by
# the serial the role gave it in Proxmox (the disk's name), never by its device name, which depends on slot order.
#
# Usage: setup-data-disk <serial> <filesystem> <mount point>
#
# A disk with no filesystem and no partitions is formatted, labelled with the serial. A disk that already has a
# filesystem is mounted as it is, and one with partitions is left alone (exit 1), so existing data is never
# overwritten. The mount goes in /etc/fstab by UUID with nofail. Safe to re-run.
set -euo pipefail
export LC_ALL=C

if (($# != 3)); then
  echo "usage: $0 <serial> <filesystem> <mount point>" >&2
  exit 2
fi
serial=$1 fstype=$2 mnt=$3

# Proxmox passes the serial to the guest as the disk's SCSI unit serial (VPD page 0x80), which lsblk shows as
# SERIAL. Not /dev/disk/by-id: Proxmox sets device_id=drive-scsiN, so the SCSI by-id link is named after the slot.
find_disk() {
  lsblk -dnpo NAME,SERIAL | awk -v s="$serial" '$2 == s { print $1; exit }'
}

# udev may still be naming disks this early in boot.
dev=
for _ in $(seq 60); do
  dev=$(find_disk)
  [[ -n $dev ]] && break
  sleep 1
done
if [[ -z $dev ]]; then
  echo "setup-data-disk: no disk with serial '$serial'" >&2
  lsblk -dpo NAME,SERIAL,SIZE >&2
  exit 1
fi

if mountpoint -q "$mnt"; then
  echo "setup-data-disk: $mnt is already mounted"
  exit 0
fi

existing=$(blkid -o value -s TYPE "$dev" || true)
if [[ -z $existing ]]; then
  if (($(lsblk -nro NAME "$dev" | wc -l) > 1)); then
    echo "setup-data-disk: $dev ($serial) has partitions but no filesystem on the whole disk; leaving it alone" >&2
    exit 1
  fi
  command -v "mkfs.$fstype" >/dev/null || { echo "setup-data-disk: mkfs.$fstype is not installed" >&2; exit 1; }
  echo "setup-data-disk: formatting $dev ($serial) as $fstype"
  "mkfs.$fstype" -L "$serial" "$dev"
  udevadm settle || true
else
  echo "setup-data-disk: $dev ($serial) already has a $existing filesystem; mounting it as it is"
  fstype=$existing
fi

uuid=$(blkid -o value -s UUID "$dev")
mkdir -p "$mnt"
if ! awk -v m="$mnt" '$1 !~ /^#/ && $2 == m { found = 1 } END { exit !found }' /etc/fstab; then
  echo "UUID=$uuid $mnt $fstype defaults,nofail 0 2" >> /etc/fstab
  systemctl daemon-reload 2>/dev/null || true
fi
mount "$mnt"
echo "setup-data-disk: mounted $dev ($serial) on $mnt"
