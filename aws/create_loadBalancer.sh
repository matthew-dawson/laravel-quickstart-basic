#! /bin/bash

set -eux

VPCDATAFILE=vpc.data
PROJECTNAME='bluegreen'
SUBNETID0=$(grep 'SUBNETID0' $VPCDATAFILE | awk '{ print $2 }')
SUBNETID1=$(grep 'SUBNETID1' $VPCDATAFILE | awk '{ print $2 }')
SECURITYGROUPID=$(grep 'SECURITYGROUPID' $VPCDATAFILE | awk '{ print $2 }')
LOADBALANCERARN=$(aws elbv2 create-load-balancer \
    --name "$PROJECTNAME"-alb \
    --subnets "$SUBNETID0" "$SUBNETID1" \
    --security-groups "$SECURITYGROUPID" \
    | grep 'LoadBalancerArn' | awk '{ print $2 }' \
    | tr -d ',"')



