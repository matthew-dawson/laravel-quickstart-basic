#! /bin/bash

PROJECT="laravel"
REGION="eu-west-2"
#VPCID=''
#IGWID=''
#ROUTETABLEID=''
#SUBNETID0=''
#SUBNETID1=''
#NAMESPACEID=''
#OPERATIONID=''
 
set -eux 

# Determine AWS account
ACCOUNT=$(aws sts get-caller-identity \
    | grep 'Account' | awk '{ print $2 }' \
    | tr -d ',"')
echo "$ACCOUNT" > account.data

create_vpc () {

    local DATAFILE="vpc.data"
   
    if [ -e "$DATAFILE" ]; then
        echo 'VPC DATA EXISTS!!'
        exit 255
    fi

    touch "$DATAFILE"

    # Create a VPC with a 10.0.0.0/16 CIDR block
    VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
        | grep 'VpcId' \
        | awk '{ print $2 }' \
        | tr -d ',"')

    echo "VPCID $VPCID" >> "$DATAFILE"

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

    # Give the servicdiscovery service time to process
    sleep 20

    NAMESPACEID=$(aws servicediscovery get-operation \
        --operation-id "$OPERATIONID" \
        | grep 'NAMESPACE":' \
        | awk '{ print $2 }' \
        | tr -d ',"')

    echo "NAMESPACEID $NAMESPACEID" >> "$DATAFILE"

    # Create a subnet with 10.0.1.0/24 CIDR block
    aws ec2 create-subnet \
        --availability-zone "$REGION"a \
        --vpc-id "$VPCID" \
        --cidr-block 10.0.1.0/24

    # Create a subnet with 10.0.0.0/24 CIDR block
    aws ec2 create-subnet \
        --availability-zone "$REGION"b \
        --vpc-id "$VPCID" \
        --cidr-block 10.0.0.0/24

    IGWID=$(aws ec2 create-internet-gateway \
        | grep 'InternetGatewayId' \
        | awk '{ print $2 }' \
        | tr -d ',"')

    echo "IGWID $IGWID" >> "$DATAFILE"

    # Attach the InternetGateway to the VPC
    aws ec2 attach-internet-gateway \
        --vpc-id "$VPCID" \
        --internet-gateway-id "$IGWID"

    # Create a route table for the VPC
    ROUTETABLEID=$(aws ec2 create-route-table --vpc-id "$VPCID" \
        | grep 'RouteTableId' \
        | awk '{ print $2 }' \
        | tr -d ',"')

    echo "ROUTETABLEID $ROUTETABLEID" >> "$DATAFILE"

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

    echo "SUBNETID0 $SUBNETID0" >> "$DATAFILE"

    SUBNETID1=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPCID" \
        --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' \
        | grep 'ID"' \
        | awk '{ print $2 }' \
        | tr -d ',"' \
        | tail -n1)

    echo "SUBNETID1 $SUBNETID1" >> "$DATAFILE"

    # Associate the subnets with the route table
    aws ec2 associate-route-table \
        --subnet-id "$SUBNETID0" \
        --route-table-id "$ROUTETABLEID"

    aws ec2 associate-route-table \
        --subnet-id "$SUBNETID1" \
        --route-table-id "$ROUTETABLEID"

    # Store the IDs locally
    SECURITYGROUPID=$(aws ec2 describe-security-groups \
        --filters Name=vpc-id,Values="$VPCID" \
        --query 'SecurityGroups[*].[GroupId]' \
        --output text)

    echo "SECURITYGROUPID $SECURITYGROUPID" >> "$DATAFILE"

    # Allow ingress on port 80 from 0.0.0.0/0
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITYGROUPID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0

}

create_ecrRepos () {

    for i in {app,db,webserver}; do
        REPOSITORYUI=$(aws ecr create-repository \
        --repository-name "$PROJECT/$i" \
        --image-scanning-configuration scanOnPush=false \
        --region "$REGION" \
        | grep 'repositoryUri' \
        | awk '{ print $2 }' \
        | tr -d ',"')

        sed -i "#image# s#: .*# :\"$REPOSITORYUI\",#" tasks/$i-task.json
    done

}

create_codeBuildServiceRole () {

    aws iam create-role \
        --role-name CodeBuildServiceRole \
        --assume-role-policy-document file://codebuild/create-role.json

    aws iam put-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-name CodeBuildServiceRolePolicy \
        --policy-document file://codebuild/create-role-policy.json

    # Add secrets manager permissions to code build role
    aws iam attach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

    # Add ECR permissions to the code build role
    aws iam attach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds
}

create_codeBuildProject () {

    # Give the permissions time to apply
    sleep 20

    aws codebuild create-project \
        --cli-input-json file://codebuild/"$PROJECT"-project.json

    ## Run the build to populate the ECR repos
    aws codebuild start-build \
        --project-name "$PROJECT" \
        --buildspec-override buildspec-full.yml

}

create_ecsCluster () {

    CLUSTERNAME="$PROJECT"-cluster
    local DATAFILE="cluster.data"

    if [ -e "$DATAFILE" ]; then
        echo 'CLUSTER DATA EXISTS!!'
        exit 255
    fi

    touch "$DATAFILE"

    CLUSTERARN=$(aws ecs create-cluster --cluster-name "$CLUSTERNAME" \
        | grep 'clusterArn' | awk '{ print $2 }' | tr -d ',"')

        echo "CLUSTERNAME $CLUSTERNAME" >> "$DATAFILE"
        echo "CLUSTERARN $CLUSTERARN" >> "$DATAFILE"

}

create_efs () {

    local DATAFILE="efs.data"
    FILESYSTEMID=$(aws efs create-file-system \
        --no-encrypted \
        --region "$REGION" \
        | grep 'FileSystemId' | awk '{ print $2 }' \
        | tr -d ',"')

    # Give it time to become available
    sleep 30

    # Create a Mount Target
    MOUNTTARGETID0=$(aws efs create-mount-target \
        --file-system-id "$FILESYSTEMID" \
        --subnet-id "$SUBNETID0" \
        --security-group "$SECURITYGROUPID" \
        --region "$REGION" \
        | grep 'MountTargetId' | awk '{ print $2 }' \
        | tr -d ',"')

    MOUNTTARGETID1=$(aws efs create-mount-target \
        --file-system-id "$FILESYSTEMID" \
        --subnet-id "$SUBNETID1" \
        --security-group "$SECURITYGROUPID" \
        --region "$REGION" \
        | grep 'MountTargetId' | awk '{ print $2 }' \
        | tr -d ',"')

    ## Update the task definition for the db to consume this EFS
    sed -i "/fileSystemId/ s/: .*/: \"$FILESYSTEMID\"/" tasks/db-task.json

    echo "FILESYSTEMID $FILESYSTEMID" > "$DATAFILE"
    echo "MOUNTTARGETID0 $MOUNTTARGETID0" >> "$DATAFILE"
    echo "MOUNTTARGETID1 $MOUNTTARGETID1" >> "$DATAFILE"

}

create_ecsTaskExecutionRole () {

    local ROLENAME="ecsTaskExecutionRole"
    local ROLEARN=''
        ROLEARN=$(aws iam create-role \
        --region "$REGION" \
        --role-name "$ROLENAME" \
        --assume-role-policy-document file://task-execution-assume-role.json \
        | grep 'Arn' \
        | awk '{ print $2 }' \
        | tr -d ',"' )

    for i in {app,db,webserver}; do
        sed -i "#executionRoleArn# s#: .*# :\"$ROLEARN\",#" tasks/$i-task.json
     done

    # Attach the role policy to the role
    aws iam attach-role-policy \
    --region "$REGION" \
    --role-name "$ROLENAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

}

create_ecsTaskRegistrations () {

    aws ecs register-task-definition --cli-input-json file://tasks/app-task.json
    aws ecs register-task-definition --cli-input-json file://tasks/webserver-task.json
    aws ecs register-task-definition --cli-input-json file://tasks/db-task.json

}

create_cloudwatchLogGroups() {

    for i in {app,db,webserver}; do
        aws logs create-log-group \
            --log-group-name /ecs/"$PROJECT"-"$i"
    done

    aws logs create-log-group \
        --log-group-name /codebuild/"$PROJECT"

}

create_codePipelineServiceRole () {

    aws iam create-role \
        --role-name CodePipelineServiceRole \
        --assume-role-policy-document file://codepipeline/create-role.json

    aws iam attach-role-policy \
        --role-name CodePipelineServiceRole \
        --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess


}

create_artifactS3Bucket () {

    aws s3 mb s3://codepipeline-eu-west-2-laravel

}

main () {
    ## TODO Populate the docker credentials within secrets manager
    create_vpc
    create_ecrRepos
    create_cloudwatchLogGroups
    create_artifactS3Bucket
    create_efs
    create_ecsCluster
    create_ecsTaskExecutionRole
    create_ecsTaskRegistrations
    create_codeBuildServiceRole
    create_codeBuildProject
    create_codePipelineServiceRole
    # TODO Create Load Balancer
    # TODO Create load balancer target group
    # TODO Create ECS Services
    # TODO Create Code Pipeline Project
    # TODO Create Code Deploy Service Role
    # TODO Create Code Deploy build
    # TODO Create Code Pipeline

    echo "--==SUCCESS==--"
}

main
