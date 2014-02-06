#!/bin/bash

# The only case where this script would fail is:
# mkfs.vfat /dev/mmcblk1 then repartitioning to create an empty ext2 partition

DEF_UID=$(grep "^UID_MIN" /etc/login.defs |  tr -s " " | cut -d " " -f2)
DEF_GID=$(grep "^GID_MIN" /etc/login.defs |  tr -s " " | cut -d " " -f2)
DEVICEUSER=$(getent passwd $DEF_UID | sed 's/:.*//')
MNT=/run/user/$DEF_UID/media/sdcard

if [ -z "${ACTION}" ] || [ -z "${DEVNAME}" ] || [ -z "${ID_FS_UUID}" ] || [ -z "${ID_FS_TYPE}" ]; then
	exit 1
fi

if [ "$ACTION" = "add" ]; then
	su $DEVICEUSER -c "mkdir -p $MNT/${ID_FS_UUID}"
	case "${ID_FS_TYPE}" in
		vfat|ntfs|exfat)
			mount ${DEVNAME} $MNT/${ID_FS_UUID} -o uid=$DEF_UID,gid=$DEF_GID,sync
			if [ $? != 0 ]; then
				/bin/rmdir $MNT/${ID_FS_UUID}
			fi

			;;
		*)
			mount ${DEVNAME} $MNT/${ID_FS_UUID} -o sync
			if [ $? != 0 ]; then
				/bin/rmdir $MNT/${ID_FS_UUID}
			fi

			chown $DEF_UID:$DEF_GID $MNT
			;;
	esac
else
	DIR=$(mount | grep -w ${DEVNAME} | cut -d \  -f 3)
	umount $DIR

	if [ $? != 0 ]; then
		umount -l $DIR
	fi

	/bin/rmdir $DIR
fi

