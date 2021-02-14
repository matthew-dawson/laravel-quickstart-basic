#! /bin/bash

set -eux

SUBNETID0=$(grep 'SUBNETID0' vpc.data | awk '{ print $2 }')
SUBNETID1=$(grep 'SUBNETID1' vpc.data | awk '{ print $2 }')
SECURITYGROUPID=$(grep 'SECURITYGROUPID' vpc.data | awk '{ print $2 }')

# Create EFS File System
FILESYSTEMID=$(aws efs create-file-system \
    --no-encrypted \
    --region eu-west-2 \
    | grep 'FileSystemId' | awk '{ print $2 }' \
    | tr -d ',"')

# Give it time to become available
sleep 15

# Create a Mount Target
MOUNTTARGETID0=$(aws efs create-mount-target \
    --file-system-id "$FILESYSTEMID" \
    --subnet-id "$SUBNETID0" \
    --security-group "$SECURITYGROUPID" \
    --region eu-west-2 \
    | grep 'MountTargetId' | awk '{ print $2 }' \
    | tr -d ',"')

MOUNTTARGETID1=$(aws efs create-mount-target \
    --file-system-id "$FILESYSTEMID" \
    --subnet-id "$SUBNETID1" \
    --security-group "$SECURITYGROUPID" \
    --region eu-west-2 \
    | grep 'MountTargetId' | awk '{ print $2 }' \
    | tr -d ',"')

## Update the task definition for the db to consume this EFS
sed -i "#filesystemId# s#: .*# :\"$FILESYSTEMID\",#" tasks/db-task.json


echo "FILESYSTEMID $FILESYSTEMID" > efs.data
echo "MOUNTTARGETID0 $MOUNTTARGETID0" >> efs.data
echo "MOUNTTARGETID1 $MOUNTTARGETID1" >> efs.data
