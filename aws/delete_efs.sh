#! /bin/bash

set -eux

FILESYSTEMID=$(grep 'FILESYSTEMID' efs.data | awk '{ print $2 }')
MOUNTTARGETID0=$(grep 'MOUNTTARGETID0' efs.data | awk '{ print $2 }')
MOUNTTARGETID1=$(grep 'MOUNTTARGETID1' efs.data | awk '{ print $2 }')

aws efs delete-mount-target \
    --mount-target-id "$MOUNTTARGETID0" \
    --region eu-west-2

aws efs delete-mount-target \
    --mount-target-id "$MOUNTTARGETID1" \
    --region eu-west-2

# Give the filesystem time to dismount the mount targets
sleep 30

aws efs delete-file-system \
    --file-system-id "$FILESYSTEMID" \
    --region eu-west-2

rm efs.data
