#! /bin/bash

set -eux
DATAFILE=vpc.data
VPCID=$(grep 'VPCID' $DATAFILE \
    | awk '{ print $2 }')
IGWID=$(grep 'IGWID' $DATAFILE \
    | awk '{ print $2 }')
ROUTETABLEID=$(grep 'ROUTETABLEID' $DATAFILE \
    | awk '{ print $2 }')
SECURITYGROUPID=$(grep 'SECURITYGROUPID' $DATAFILE \
    | awk '{ print $2 }')
NAMESPACEID=$(grep 'NAMESPACEID' $DATAFILE \
    | awk '{print $2 }')

# Delete the security group
aws ec2 delete-security-group --group-id "$SECURITYGROUPID"

# Delete subnets
for i in $(grep 'SUBNET' $DATAFILE \
    | awk '{ print $2 }') ; do \
    aws ec2 delete-subnet --subnet-id "$i"
done

# Delete the route table
aws ec2 delete-route-table --route-table-id "$ROUTETABLEID"

# Detach the IGW from the VPC
aws ec2 detach-internet-gateway --internet-gateway-id "$IGWID" --vpc-id "$VPCID"

# Delete the IGW
aws ec2 delete-internet-gateway --internet-gateway-id "$IGWID"

# Delete the private namespace
aws servicediscovery delete-namespace --id "$NAMESPACEID"

# Allow the service discovery service time to delete the namespace.
sleep 20

# Delete the security group
aws ec2 delete-security-group --group-id "$(grep SECURITYGROUPID vpc.data \
    | awk '{ print $2 }')"

# Delete the VPC
aws ec2 delete-vpc --vpc-id "$VPCID"

rm vpc.data
