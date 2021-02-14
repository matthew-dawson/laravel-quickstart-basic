#! /bin/bash
set -eux

DATAFILE=vpc.data
VPCID=''
IGWID=''
ROUTETABLEID=''
SUBNETID0=''
SUBNETID1=''
NAMESPACEID=''
OPERATIONID=''

if [ -e $DATAFILE ]; then
    echo 'VPC DATA EXISTS!!'
    exit 255
fi

touch $DATAFILE

# Create a VPC with a 10.0.0.0/16 CIDR block
VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
    | grep 'VpcId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

echo "VPCID $VPCID" >> $DATAFILE

# Enable DNS Support
aws ec2 modify-vpc-attribute --enable-dns-support \
    --vpc-id "$VPCID"

# Enable DNS Hostnames
aws ec2 modify-vpc-attribute --enable-dns-hostnames \
    --vpc-id "$VPCID"

# Create .local private hosted zone using service discovery
OPERATIONID=$(aws servicediscovery create-private-dns-namespace \
    --name local \
    --vpc "$VPCID" \
    | grep 'OperationId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

sleep 20

NAMESPACEID=$(aws servicediscovery get-operation \
    --operation-id "$OPERATIONID" \
    | grep 'NAMESPACE":' \
    | awk '{ print $2 }' \
    | tr -d ',"')

echo "NAMESPACEID $NAMESPACEID" >> $DATAFILE

# Create a subnet with 10.0.1.0/24 CIDR block
aws ec2 create-subnet \
    --availability-zone 'eu-west-2a' \
    --vpc-id "$VPCID" \
    --cidr-block 10.0.1.0/24

# Create a subnet with 10.0.0.0/24 CIDR block
aws ec2 create-subnet \
    --availability-zone 'eu-west-2b' \
    --vpc-id "$VPCID" \
    --cidr-block 10.0.0.0/24

IGWID=$(aws ec2 create-internet-gateway \
    | grep 'InternetGatewayId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

echo "IGWID $IGWID" >> $DATAFILE

# Attach the InternetGateway to the VPC
aws ec2 attach-internet-gateway \
    --vpc-id "$VPCID" \
    --internet-gateway-id "$IGWID"

# Create a route table for the VPC
ROUTETABLEID=$(aws ec2 create-route-table --vpc-id "$VPCID" \
    | grep 'RouteTableId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

echo "ROUTETABLEID $ROUTETABLEID" >> $DATAFILE

# Create default route entry
aws ec2 create-route \
    --route-table-id "$ROUTETABLEID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGWID"

# Determine subnet IDs
SUBNETID0=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPCID" \
    --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' \
    | grep 'ID"' \
    | awk '{ print $2 }' \
    | tr -d ',"' \
    | head -n1)

echo "SUBNETID0 $SUBNETID0" >> $DATAFILE

SUBNETID1=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPCID" \
    --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' \
    | grep 'ID"' \
    | awk '{ print $2 }' \
    | tr -d ',"' \
    | tail -n1)

echo "SUBNETID1 $SUBNETID1" >> $DATAFILE

# Associate the subnets with the route table
aws ec2 associate-route-table \
    --subnet-id "$SUBNETID0" \
    --route-table-id "$ROUTETABLEID"

aws ec2 associate-route-table \
    --subnet-id "$SUBNETID1" \
    --route-table-id "$ROUTETABLEID"

# Store the IDs locally
SECURITYGROUPID=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$VPCID \
    --query 'SecurityGroups[*].[GroupId]' \
    --output text)

echo "SECURITYGROUPID $SECURITYGROUPID" >> $DATAFILE

aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITYGROUPID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

## TODO Add an inbound rule with type NFS on port 2049 to the security group
## I believe this is already covered by the all rule, but will leave this here
## until further testing is completed
