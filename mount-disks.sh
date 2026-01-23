#!/usr/bin/env sh

LOG_TAG="startup-disk-mount"

log() {
  echo "[$LOG_TAG] $1"
  logger -t "$LOG_TAG" "$1"
}

# Expect DISKS env var: "disk-a disk-b disk-c"
DISKS="${DISKS:-}"

if [ -z "$DISKS" ]; then
  log "No attached disks specified. Nothing to mount."
  exit 0
fi

log "Disks to mount: $DISKS"

for DISK_NAME in $DISKS; do
  DEVICE="/dev/disk/by-id/google-${DISK_NAME}"
  MOUNT_POINT="/mnt/${DISK_NAME}"

  log "Processing disk '${DISK_NAME}'"

  mkdir -p "$MOUNT_POINT"

  # Wait for device to appear
  log "Waiting for device ${DEVICE}"
  for i in {1..30}; do
    [ -e "$DEVICE" ] && break
    sleep 1
  done

  if [ ! -e "$DEVICE" ]; then
    log "ERROR: Device ${DEVICE} not found, skipping"
    continue
  fi

  # Format if needed
  if ! blkid "$DEVICE" >/dev/null 2>&1; then
    log "No filesystem detected on ${DEVICE}, formatting ext4"
    mkfs.ext4 -F "$DEVICE"
  else
    log "Filesystem already exists on ${DEVICE}"
  fi

  # Persist mount
  if ! grep -qs "$DEVICE" /etc/fstab; then
    log "Adding ${DEVICE} to /etc/fstab"
    echo "${DEVICE} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
  else
    log "fstab entry already exists for ${DEVICE}"
  fi

  # Mount
  if mountpoint -q "$MOUNT_POINT"; then
    log "${MOUNT_POINT} already mounted"
  else
    log "Mounting ${DEVICE} at ${MOUNT_POINT}"
    mount "$MOUNT_POINT"
  fi
done

log "Disk mounting complete"
