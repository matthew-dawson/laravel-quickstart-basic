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

if [ -e vpc.data ]; then
    echo 'VPC DATA EXISTS!!'
    exit 255
fi

# Create a VPC with a 10.0.0.0/16 CIDR block
VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
    | grep 'VpcId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

# Enable DNS Support
modify-vpc-attribute --enable-dns-support \
    --vpc-id "$VPCID"

# Enable DNS Hostnames
modify-vpc-attribute --enable-dhs-hostnames \
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
    | grep 'NAMESPACE' \
    | awk '{ print $2 }' \
    | tr -d ',"')


# Create a subnet with 10.0.1.0/24 CIDR block
aws ec2 create-subnet --availability-zone 'eu-west-2a' --vpc-id "$VPCID" --cidr-block 10.0.1.0/24

# Create a subnet with 10.0.0.0/24 CIDR block
aws ec2 create-subnet --availability-zone 'eu-west-2b' --vpc-id "$VPCID" --cidr-block 10.0.0.0/24

IGWID=$(aws ec2 create-internet-gateway \
    | grep 'InternetGatewayId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

# Attach the InternetGateway to the VPC
aws ec2 attach-internet-gateway --vpc-id "$VPCID" --internet-gateway-id "$IGWID"

# Create a route table for the VPC
ROUTETABLEID=$(aws ec2 create-route-table --vpc-id "$VPCID" \
    | grep 'RouteTableId' \
    | awk '{ print $2 }' \
    | tr -d ',"')

# Create default route entry
aws ec2 create-route --route-table-id "$ROUTETABLEID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGWID"

# Determine subnet IDs
SUBNETID0=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' \
    | grep 'ID"' \
    | awk '{ print $2 }' \
    | tr -d ',"' \
    | head -n1)

SUBNETID1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' \
    | grep 'ID"' \
    | awk '{ print $2 }' \
    | tr -d ',"' \
    | tail -n1)

# Associate the subnets with the route table
aws ec2 associate-route-table  --subnet-id "$SUBNETID0" --route-table-id "$ROUTETABLEID"

aws ec2 associate-route-table  --subnet-id "$SUBNETID1" --route-table-id "$ROUTETABLEID"


# Store the IDs locally
echo "VPCID $VPCID" > $DATAFILE
echo "IGWID $IGWID" >> $DATAFILE
echo "ROUTETABLEID $ROUTETABLEID" >> $DATAFILE
echo "SUBNETID0 $SUBNETID0" >> $DATAFILE
echo "SUBNETID1 $SUBNETID1" >> $DATAFILE
echo "SECURITYGROUPID $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPCID --query 'SecurityGroups[*].[GroupId]' --output text)" >> $DATAFILE
echo "NAMESPACEID $NAMESPACEID" >> $DATAFILE

aws ec2 authorize-security-group-ingress 
    --group-id $SECURITYGROUPID \
    --protocol tcp \
    --port http \
    --cidr 0.0.0.0/0

## TODO Add an inbound rule with type NFS on port 2049 to the security group
