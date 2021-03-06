#!/bin/bash

# The only case where this script would fail is:
# mkfs.vfat /dev/mmcblk1 then repartitioning to create an empty ext2 partition

DEF_UID=$(grep "^UID_MIN" /etc/login.defs |  tr -s " " | cut -d " " -f2)
DEF_GID=$(grep "^GID_MIN" /etc/login.defs |  tr -s " " | cut -d " " -f2)
DEVICEUSER=$(getent passwd $DEF_UID | sed 's/:.*//')
MNT=/media/sdcard
MOUNT_OPTS="dirsync,noatime,users"
# options: --discard=once --priority 10
SWAP_OPTS="--discard --priority 10"
ACTION=$1
DEVNAME=$2

if [ -z "${ACTION}" ]; then
    systemd-cat -t mount-sd /bin/echo "ERROR: Action needs to be defined."
    exit 1
fi

if [ -z "${DEVNAME}" ]; then
    systemd-cat -t mount-sd /bin/echo "ERROR: Device name needs to be defined."
    exit 1
fi

systemd-cat -t mount-sd /bin/echo "Called to ${ACTION} ${DEVNAME}"

if [ "$ACTION" = "add" ]; then

    eval "$(/sbin/blkid -c /dev/null -o export /dev/$2)"

    if [ -z "${TYPE}" ]; then
        systemd-cat -t mount-sd /bin/echo "ERROR: Filesystem type missing for ${DEVNAME}."
        exit 1
    fi

    if [ "${TYPE}" = "swap" ]; then
        SWAP=$(grep -w ${DEVNAME} /proc/swaps | cut -d \  -f 1)
        if [ -n "$SWAP" ]; then
            systemd-cat -t mount-sd /bin/echo "${DEVNAME} already used as swap space, ignoring"
            exit 0
        fi
        systemd-cat -t mount-sd /bin/echo "${DEVNAME} seems to be swap space"
        swapon $SWAP_OPTS ${DEVNAME}
        systemd-cat -t mount-sd /bin/echo "Finished ${ACTION}ing ${DEVNAME} of type ${TYPE} as swap space"
        exit 0
    fi

    if [ -z "${UUID}" ]; then
        # In case device does not have UUID lets create one for it based on
        # the card identification.
        PKNAME=$(lsblk -n -o PKNAME ${DEVNAME})
        if [ -e "/sys/block/${PKNAME}/device/cid" ]; then
            CID=$(cat /sys/block/${PKNAME}/device/cid)
            if [ -n "${CID}" ]; then
                IDNAME=$(lsblk -n -o NAME ${DEVNAME})
                UUID="${CID}-${IDNAME}"
            fi
        fi

        if [ -z "${UUID}" ]; then
            # Exit here as in the future there might be things like USB OTG disks or
            # sdcards attached via adapter that might behave differently and needs special case
            # in case such happens fail so we don't break anything.
            systemd-cat -t mount-sd /bin/echo "ERROR: Could not find or generate UUID for device ${DEVNAME}."
            exit 1
        fi
    fi

    DIR=$(grep -w ${DEVNAME} /proc/mounts | cut -d \  -f 2)
    if [ -n "$DIR" ]; then
        systemd-cat -t mount-sd /bin/echo "${DEVNAME} already mounted on ${DIR}, ignoring"
        exit 0
    fi

    test -d $MNT/${UUID} || mkdir -p $MNT/${UUID}
    chown $DEF_UID:$DEF_GID $MNT $MNT/${UUID}
    touch $MNT/${UUID}

    case "${TYPE}" in
	vfat|exfat)
	    mkdir -p /opt/alien/storage/sdcard1/
	    #mount ${DEVNAME} $MNT/${UUID} -o uid=$DEF_UID,gid=$DEF_GID,$MOUNT_OPTS,utf8,flush,discard || /bin/rmdir $MNT/${UUID}
	    mount ${DEVNAME} /opt/alien/storage/sdcard1/ -o uid=1015,gid=1015,fmask=002,dmask=002,$MOUNT_OPTS,utf8,flush,discard || /bin/rmdir $MNT/${UUID}
	    ;;
	# NTFS support has not been tested but it's being left to please the ego of an engineer!
	ntfs)
	    mount ${DEVNAME} $MNT/${UUID} -o uid=$DEF_UID,gid=$DEF_GID,$MOUNT_OPTS,utf8 || /bin/rmdir $MNT/${UUID}
	    ;;
	*)
	    mount ${DEVNAME} $MNT/${UUID} -o $MOUNT_OPTS || /bin/rmdir $MNT/${UUID}
	    ;;
    esac
    test -d $MNT/${UUID} && touch $MNT/${UUID}
    systemd-cat -t mount-sd /bin/echo "Finished ${ACTION}ing ${DEVNAME} of type ${TYPE} at $MNT/${UUID}"

else
    DIR=$(grep -w ${DEVNAME} /proc/mounts | cut -d \  -f 2)
    if [ -n "${DIR}" ] ; then
        if [ "${DIR##$MNT}" = "${DIR}" ]; then
            systemd-cat -t mount-sd /bin/echo "${DEVNAME} mountpoint ${DIR} is not under ${MNT}, ignoring"
            exit 0
        fi
        umount $DIR || umount -l $DIR
        systemd-cat -t mount-sd /bin/echo "Finished ${ACTION}ing ${DEVNAME} at ${DIR}"
    else
        SWAP=$(grep -w ${DEVNAME} /proc/swaps | cut -d \  -f 1)
        if [ -z "$SWAP" ]; then
            systemd-cat -t mount-sd /bin/echo "${DEVNAME} in not currently used as swap space, ignoring"
            exit 0
        fi
        swapoff "${SWAP}"
        systemd-cat -t mount-sd /bin/echo "Finished ${ACTION}ing ${DEVNAME} as swap space"
    fi
fi

