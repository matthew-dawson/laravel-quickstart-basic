#! /bin/bash

set -eux

PROJECT="laravel"
REGION="eu-west-2"
VPCID=''
IGWID=''
ROUTETABLEID=''
NAMESPACEID=''
SUBNETID0=''
SUBNETID1=''

delete_vpc () {
    local DATAFILE="vpc.data"
    VPCID=$(grep 'VPCID' "$DATAFILE" \
        | awk '{ print $2 }')
    IGWID=$(grep 'IGWID' "$DATAFILE" \
        | awk '{ print $2 }')
    ROUTETABLEID=$(grep 'ROUTETABLEID' "$DATAFILE" \
        | awk '{ print $2 }')
    NAMESPACEID=$(grep 'NAMESPACEID' "$DATAFILE" \
        | awk '{print $2 }')
    #SECURITYGROUPID=$(grep 'SECURITYGROUPID' "$DATAFILE" \
    #    | awk '{ print $2 }')
 
    # Populate subnetids
    SUBNETID0=$(grep 'SUBNETID0' "$DATAFILE" \
        | awk '{ print $2 }')
    SUBNETID1=$(grep 'SUBNETID1' "$DATAFILE" \
        | awk '{ print $2 }')


    ## Delete the security group
    ## Default security group cannot be deleted by a user.
    # aws ec2 delete-security-group --group-id "$SECURITYGROUPID"

    # Delete subnets
    aws ec2 delete-subnet --subnet-id "$SUBNETID0"
    aws ec2 delete-subnet --subnet-id "$SUBNETID1"

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

    # Delete the VPC
    aws ec2 delete-vpc --vpc-id "$VPCID"

    rm "$DATAFILE"
}

delete_ecrRepos () {

    for i in {app,db,webserver}; do
        aws ecr delete-repository \
        --repository-name "$PROJECT"/"$i" \
        --force
        done

}

delete_cloudwatchLogGroups () {

    # Delete log groups for ECS
    for i in {app,db,webserver}; do
        aws logs delete-log-group \
        --log-group-name /ecs/"$PROJECT"-"$i"
    done
    
    # Delete log group for code build
    aws logs delete-log-group \
        --log-group-name /codebuild/"$PROJECT"

}

delete_efs () {

    local DATAFILE="efs.data"
    FILESYSTEMID=$(grep 'FILESYSTEMID' "$DATAFILE" | awk '{ print $2 }')
    MOUNTTARGETID0=$(grep 'MOUNTTARGETID0' "$DATAFILE" | awk '{ print $2 }')
    MOUNTTARGETID1=$(grep 'MOUNTTARGETID1' "$DATAFILE" | awk '{ print $2 }')

    aws efs delete-mount-target \
        --mount-target-id "$MOUNTTARGETID0" \
        --region "$REGION"

    aws efs delete-mount-target \
        --mount-target-id "$MOUNTTARGETID1" \
        --region "$REGION"

    # Give the filesystem time to dismount the mount targets
    sleep 60

    aws efs delete-file-system \
        --file-system-id "$FILESYSTEMID" \
        --region "$REGION"

    rm "$DATAFILE"

}

delete_ecsTaskExecutionRole () {

    ## Detach policies first
    aws iam detach-role-policy \
        --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    aws iam delete-role \
        --role-name ecsTaskExecutionRole

}

delete_codeBuildServiceRole () {

    ## Detach policies first
    aws iam delete-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-name CodeBuildServiceRolePolicy

    # Detach the Secrets Manager Policy
    aws iam detach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

    # Detach the ECR policy
    aws iam detach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds

    aws iam delete-role \
        --role-name CodeBuildServiceRole

}

delete_codeBuildProject () {

    aws codebuild delete-project \
        --name "$PROJECT"

}

delete_ecsCluster () {

    local DATAFILE="cluster.data"
    CLUSTERNAME=$(grep 'CLUSTERNAME' "$DATAFILE" \
        | awk '{ print $2 }' )

    aws ecs delete-cluster \
        --cluster "$CLUSTERNAME"

    rm "$DATAFILE"

}

delete_codePipelineServiceRole () {

    ## Detach policies first
    aws iam delete-role-policy \
        --role-name CodePipelineServiceRole \
        --policy-name CodePipelineServiceRolePolicy

# Detach the ECR policy
    aws iam detach-role-policy \
        --role-name CodePipelineServiceRole \
        --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess

    # Delete the role
    aws iam delete-role \
        --role-name CodePipelineServiceRole

}

delete_artifactS3Bucket () {

    aws s3 rb s3://codepipeline-eu-west-2-laravel

}

delete_codePipeline () {

    aws codepipeline delete-pipeline --name laravel

}

main () {
    delete_codePipeline
    delete_artifactS3Bucket
    delete_codePipelineServiceRole
    # TODO Delete Load Balancer
    # TODO Delete the load balancer target groups
    # TODO Delete ECS Services
    # TODO Delete/deregister task definitions
    delete_ecsTaskExecutionRole
    delete_ecsCluster
    delete_codeBuildProject
    delete_codeBuildServiceRole
    # TODO Delete Code Deploy build
    delete_cloudwatchLogGroups
    delete_efs
    delete_ecrRepos
    delete_vpc
    # TODO Remove Docker credentials from secrets manager

    echo "--==SUCCESS==--"
}

main
