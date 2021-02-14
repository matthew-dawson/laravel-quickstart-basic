#! /bin/bash

set -eux 

DATAFILE=cluster.data
CLUSTERNAME=$(grep 'CLUSTERNAME' $DATAFILE \
    | awk '{ print $2 }' )

aws ecs delete-cluster --cluster "$CLUSTERNAME"

rm $DATAFILE
