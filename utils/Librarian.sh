#!/usr/bin/env bash

# Librarian.sh:
# Mounts or unmounts a private samba share drive. with ease.

MOUNT_PATH="smb://server_address/share_name"

# Function to mount the Samba share
mount_samba() {
	if gio mount -l | grep -q "$MOUNT_PATH"; then
		echo "The Samba share is already mounted."
	else
		echo "Mounting Samba share..."
		gio mount $MOUNT_PATH
		echo "Samba share mounted successfully."
	fi
}

# Function to unmount the Samba share
unmount_samba() {
	if gio mount -l | grep -q "$MOUNT_PATH"; then
		echo "Unmounting Samba share..."
		gio mount -u $MOUNT_PATH
		echo "Samba share unmounted successfully."
	else
		echo "The Samba share is not mounted."
	fi
}

case "$1" in
	mount)
		mount_samba
		;;
	unmount)
		unmount_samba
		;;
	*)
		echo "Invalid option. Use 'mount' or 'unmount'."
		exit 1
		;;
esac
