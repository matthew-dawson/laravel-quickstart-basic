#! /bin/bash

set -eux
DATAFILE=codeDeploy.data
ROLENAME=CodeDeployServiceRole
IAMROLEARN=''

IAMROLEARN=$(aws iam create-role --role-name "$ROLENAME" --assume-role-policy-document file://CodeDeployLaravel-Trust.json \
    | grep 'Arn' | awk '{ print $2 }' | tr -d ',"')

aws iam attach-role-policy --role-name $ROLENAME --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS

echo "ROLENAME $ROLENAME" > $DATAFILE
echo "IAMROLEARN $IAMROLEARN" >> $DATAFILE
