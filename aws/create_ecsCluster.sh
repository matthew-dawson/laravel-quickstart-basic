#! /bin/bash

set -eux
PROJECT=laravel
CLUSTERNAME="$PROJECT"-cluster
DATAFILE=cluster.data

if [ -e $DATAFILE ]; then
    echo 'CLUSTER DATA EXISTS!!'
    exit 255
fi

touch $DATAFILE

CLUSTERARN=$(aws ecs create-cluster --cluster-name "$CLUSTERNAME" \
    | grep 'clusterArn' | awk '{ print $2 }' | tr -d ',"')

echo "CLUSTERNAME $CLUSTERNAME" >> $DATAFILE
echo "CLUSTERARN $CLUSTERARN" >> $DATAFILE
