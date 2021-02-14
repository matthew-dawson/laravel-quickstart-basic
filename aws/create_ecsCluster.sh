#! /bin/bash

set -eux
PROJECT=laravel
CLUSTERNAME="$PROJECT"-cluster

CLUSTERARN=$(aws ecs create-cluster --cluster-name "$CLUSTERNAME" \
    | grep 'clusterArn' | awk '{ print $2 }' | tr -d ',"')
