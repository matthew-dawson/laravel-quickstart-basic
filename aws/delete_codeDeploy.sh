#! /bin/bash

set -eux

DATAFILE=codeDeploy.data
ROLENAME=grep 'ROLENAME' $DATAFILE | awk '{ print $2 }'

aws iam delete-role --role-name $ROLENAME
