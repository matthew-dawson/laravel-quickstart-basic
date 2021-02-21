#! /bin/bash

set -eux

DATAFILE=project.data
PROJECT="$(grep 'PROJECT' $DATAFILE | awk '{ print $2 }')"
REGION="eu-west-2"
# AWS cli v2 introduces the default usage of a pager
export AWS_PAGER=""

delete_codeDeployServiceRole () {

    ## TODO WIP
    # Detach the Code Deploy policy
    aws iam detach-role-policy \
        --role-name CodeDeployServiceRole \
        --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS

    aws iam delete-role \
        --role-name CodeDeployServiceRole

}

delete_codePipeline () {

    ## TODO
    aws codepipeline delete-pipeline --name "$PROJECT"

}

delete_ecsServices () {

    ## TODO
    for i in {app,db,webserver}; do
        aws ecs delete-service \
            --cluster "$(grep 'CLUSTERNAME' $DATAFILE \
            | awk '{ print $2 }')" \
            --service "$i"-service \
            --force

        ## Allow the service time to de-register
        sleep 30

        local SERVICE=''
        case $i in
            app)
                SERVICE='APP'
                ;;
            db)
                SERVICE='DB'
                ;;
            webservice)
                SERVICE='WEBSERVICE'
                ;;
        esac

        ## Delete the nameservice service_id from the servicediscovery service
        local SERVICE_DISCOVERY_SERVICE_ID=$(grep "$SERVICE"_SERVICE_ID \
            $DATAFILE \
            | awk '{ print $2 }')

        aws servicediscovery delete-service --id $SERVICE_DISCOVERY_SERVICE_ID


    done

}

delete_load_balancers () {

    delete_listener () {
        local LISTENER_ARN=$1

        aws elbv2 delete-listener \
        --listener-arn $LISTENER_ARN
    }

    delete_target_group() {
        local TARGET_GROUP_ARN=$1
        aws elbv2 delete-target-group \
            --target-group-arn $TARGET_GROUP_ARN
    }

    delete_load_balancer () {
        local LOAD_BALANCER_ARN=$1
        aws elbv2 delete-load-balancer \
            --load-balancer-arn $LOAD_BALANCER_ARN
    }

    for SERVICE in {APP,DB,WEB}; do
        delete_listener $(grep "${SERVICE}_LISTENER_ARN" $DATAFILE \
            | awk '{ print $2 }')
        delete_target_group $(grep "${SERVICE}_TARGETGROUP_BLUE" $DATAFILE \
            | awk '{ print $2 }')
        delete_target_group $(grep "${SERVICE}_TARGETGROUP_GREEN" $DATAFILE \
            | awk '{ print $2 }')
    done

    for TYPE in {INTERNAL,INTERNET}; do
        delete_load_balancer $(grep "${TYPE}_LOADBALANCER_ARN" $DATAFILE \
            | awk '{ print $2  }')
    done

    # Ensure we've had time to disassociate the load balancers
    # from the subnets.
    sleep 30
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

    aws iam delete-role \
        --role-name CodePipelineServiceRole

}

delete_codeBuild_project () {

    aws codebuild delete-project \
        --name "$PROJECT"

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

delete_coddebuild_project () {

    aws codebuild delete-project --name $PROJECT

}

deregister_task_definitions () {

    # Deregisters all ACTIVE task definitions for each service
    local TASK_DEF_ARN=''
    for i in {app,db,webserver}; do
        for TASK_DEF_ARN in $(aws ecs list-task-definitions \
            --family-prefix $PROJECT-$i \
            --status ACTIVE \
            | grep 'arn' \
            | awk '{ print $2 }'); do
            aws ecs deregister-task-definition \
                --task-definition $TASK_DEF_ARN
        done
    done

}

delete_ecsTaskExecutionRole () {

    ## Detach policies first
    aws iam detach-role-policy \
        --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    aws iam delete-role \
        --role-name ecsTaskExecutionRole

}

delete_ecsCluster () {

    CLUSTERNAME=$(grep 'CLUSTERNAME' "$DATAFILE" \
        | awk '{ print $2 }' )

    aws ecs delete-cluster \
        --cluster "$CLUSTERNAME"

}

delete_efs () {

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

}

delete_artifactS3Bucket () {

    aws s3 rb s3://codepipeline-eu-west-2-"$PROJECT" --force

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

delete_ecrRepos () {

    for i in {app,db,webserver}; do
        aws ecr delete-repository \
        --repository-name "$PROJECT"/"$i" \
        --force
        done

}

delete_vpc () {
    VPCID=$(grep 'VPCID' "$DATAFILE" \
        | awk '{ print $2 }')
    IGWID=$(grep 'IGWID' "$DATAFILE" \
        | awk '{ print $2 }')
    ROUTETABLEID=$(grep 'ROUTETABLEID' "$DATAFILE" \
        | awk '{ print $2 }')
    NAMESPACEID=$(grep 'NAMESPACEID' "$DATAFILE" \
        | awk '{ print $2 }')
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
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGWID" \
        --vpc-id "$VPCID"

    # Delete the IGW
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGWID"

    # Delete the private namespace
    delete_namespace() {
        local OPERATIONID=''
        OPERATIONID=$(aws servicediscovery \
            delete-namespace --id "$NAMESPACEID" \
            | awk '{ print $3 }')


        # Allow the service discovery service time to delete the namespace.
        while [[ $(aws servicediscovery \
            get-operation --operation-id $OPERATIONID \
            | grep 'Status' \
            | awk '{ print $2 }') = 'PENDING' ]]; do

            sleep 15
        done
    }

    delete_namespace

    # Delete the VPC
    aws ec2 delete-vpc --vpc-id "$VPCID"

}

main () {
    # TODO delete_codePipeline
    # TODO Delete Code Deploy Service Role
    # TODO Delete Code Deploy build
    delete_ecsServices
    delete_load_balancers
    delete_codePipelineServiceRole
    delete_codeBuild_project
    delete_codeBuildServiceRole
    deregister_task_definitions
    delete_ecsTaskExecutionRole
    delete_ecsCluster
    delete_efs
    delete_artifactS3Bucket
    delete_cloudwatchLogGroups
    delete_ecrRepos
    delete_vpc
    rm $DATAFILE

    echo "--==SUCCESS==--"
}

main
