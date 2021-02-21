#! /bin/bash

## TODO Explain this project

set -eux

## TODO : Accept project name as an argument
PROJECT="laravel"
REGION="eu-west-2"
DATAFILE="project.data"
# AWS cli v2 introduces the default usage of a pager
export AWS_PAGER=""

init () {

    if [[ ! -e $DATAFILE ]]; then
        touch $DATAFILE
        echo "PROJECT $PROJECT" > $DATAFILE
    else
        echo "$DATAFILE EXISTS!"
        exit 255
    fi

    # Determine AWS account
    ACCOUNT=$(aws sts get-caller-identity \
        | grep 'Account' \
        | awk '{ print $3 }' \
        | tr -d "'")

}

create_vpc () {

    create_namespace () {
        local OPERATIONID=''
        local NAMESPACEID=''

        OPERATIONID=$(aws servicediscovery create-private-dns-namespace \
        --name local \
        --vpc "$VPCID" \
        | awk '{ print $3 }')

        # Give the servicdiscovery service time to process
        while [[ $(aws servicediscovery get-operation \
            --operation-id "$OPERATIONID" \
            | grep 'Status' \
            | awk '{ print $2 }') = 'PENDING' ]]; do
            sleep 15
        done

        local NAMESPACEID=$(aws servicediscovery get-operation \
        --operation-id "$OPERATIONID" \
        | grep 'NAMESPACE:' \
        | awk '{ print $2 }')

        echo $NAMESPACEID

    }

    ## TODO: Improve this by utilising a query with tags
    ## -- I've made the design decision to store state locally,
    ## thus reducing the number of API calls being made to AWS.
    ## Need to denote this design decision at the beginning of
    ## this script.
    if [ $(grep 'VPCID' $DATAFILE) != '' ]; then
        echo 'VPC DATA EXISTS!!'
        exit 255
    fi

    # Create a VPC with a 10.0.0.0/16 CIDR block
    VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
        | grep 'VpcId' \
        | awk '{ print $2 }')

    echo "VPCID $VPCID" >> "$DATAFILE"

    # Enable DNS Support
    aws ec2 modify-vpc-attribute --enable-dns-support \
        --vpc-id "$VPCID"

    # Enable DNS Hostnames
    aws ec2 modify-vpc-attribute --enable-dns-hostnames \
        --vpc-id "$VPCID"

    # Create .local private hosted zone using service discovery
    NAMESPACEID=$(create_namespace)
    echo "NAMESPACEID $NAMESPACEID" >> "$DATAFILE"

    # Create a subnet with 10.0.0.0/24 CIDR block
    SUBNETID0=$(aws ec2 create-subnet \
        --availability-zone "$REGION"a \
        --vpc-id "$VPCID" \
        --cidr-block 10.0.0.0/24 \
        | grep 'SubnetId' \
        | awk '{ print $2 }')

    echo "SUBNETID0 $SUBNETID0" >> "$DATAFILE"

    # Create a subnet with 10.0.1.0/24 CIDR block
    SUBNETID1=$(aws ec2 create-subnet \
        --availability-zone "$REGION"b \
        --vpc-id "$VPCID" \
        --cidr-block 10.0.1.0/24 \
        | grep 'SubnetId' \
        | awk '{ print $2 }')

    echo "SUBNETID1 $SUBNETID1" >> "$DATAFILE"

    IGWID=$(aws ec2 create-internet-gateway \
        | grep 'InternetGatewayId' \
        | awk '{ print $2 }')

    echo "IGWID $IGWID" >> "$DATAFILE"

    # Attach the InternetGateway to the VPC
    aws ec2 attach-internet-gateway \
        --vpc-id "$VPCID" \
        --internet-gateway-id "$IGWID"

    # Create a route table for the VPC
    ROUTETABLEID=$(aws ec2 create-route-table --vpc-id "$VPCID" \
        | grep 'RouteTableId' \
        | awk '{ print $2 }')

    echo "ROUTETABLEID $ROUTETABLEID" >> "$DATAFILE"

    # Create default route entry
    aws ec2 create-route \
        --route-table-id "$ROUTETABLEID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGWID"

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
        local REPOSITORYURI=$(aws ecr create-repository \
        --repository-name "$PROJECT/$i" \
        --image-scanning-configuration scanOnPush=false \
        --region "$REGION" \
        | grep 'repositoryUri' \
        | awk '{ print $2 }')

        local SERVICE=''
        case $i in
            app)
                SERVICE='APP'
                ;;
            db)
                SERVICE='DB'
                ;;
            webserver)
                SERVICE='WEBSERVER'
                ;;
        esac

        echo "${SERVICE}_REPOSITORY_URI $REPOSITORYURI" >> $DATAFILE
    done

}

create_cloudWatchLogGroups() {

    for i in {app,db,webserver}; do
        aws logs create-log-group \
            --log-group-name /ecs/"$PROJECT"-"$i"
    done

    aws logs create-log-group \
        --log-group-name /codebuild/"$PROJECT"

}

create_artifactS3Bucket () {

    ## TODO: Randomize the bucket name
    aws s3 mb s3://codepipeline-eu-west-2-"$PROJECT"

}

create_efs () {

    FILESYSTEMID=$(aws efs create-file-system \
        --no-encrypted \
        --region "$REGION" \
        | grep 'FileSystemId' | awk '{ print $2 }')

    echo "FILESYSTEMID $FILESYSTEMID" >> "$DATAFILE"

    # Give it time to become available
    sleep 30

    # Create a Mount Target
    MOUNTTARGETID0=$(aws efs create-mount-target \
        --file-system-id "$FILESYSTEMID" \
        --subnet-id "$SUBNETID0" \
        --security-group "$SECURITYGROUPID" \
        --region "$REGION" \
        | grep 'MountTargetId' | awk '{ print $2 }')

    echo "MOUNTTARGETID0 $MOUNTTARGETID0" >> "$DATAFILE"

    MOUNTTARGETID1=$(aws efs create-mount-target \
        --file-system-id "$FILESYSTEMID" \
        --subnet-id "$SUBNETID1" \
        --security-group "$SECURITYGROUPID" \
        --region "$REGION" \
        | grep 'MountTargetId' | awk '{ print $2 }')

    echo "MOUNTTARGETID1 $MOUNTTARGETID1" >> "$DATAFILE"

}

create_ecsCluster () {

    CLUSTERNAME="$PROJECT"-cluster
    echo "CLUSTERNAME $CLUSTERNAME" >> "$DATAFILE"

    CLUSTERARN=$(aws ecs create-cluster --cluster-name "$CLUSTERNAME" \
        | grep 'clusterArn' | awk '{ print $2 }')

    echo "CLUSTERARN $CLUSTERARN" >> "$DATAFILE"

}

create_ecsTaskExecutionRole () {

    local ROLENAME="ecsTaskExecutionRole"
    ECS_TASK_ROLE_ARN=''
        ECS_TASK_ROLE_ARN=$(aws iam create-role \
        --region "$REGION" \
        --role-name "$ROLENAME" \
        --assume-role-policy-document \
        file://ecs/ecs-task-execution-assume-role.json \
        | grep 'Arn' \
        | awk '{ print $2 }')

    # Attach the role policy to the role
    aws iam attach-role-policy \
    --region "$REGION" \
    --role-name "$ROLENAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

}

create_ecsTaskRegistrations () {

    for i in {app,db,webserver}; do
        ## Populating the *-task.json from the *-task.json.tmpl
        sed "s/<ACCOUNT>/${ACCOUNT}/g" ecs/tasks/"$i"-task.json.tmpl \
            > ecs/tasks/"$i-task.json"

        sed -i "s/<PROJECT>/${PROJECT}/g" ecs/tasks/"$i"-task.json

        local SERVICE=''
        case $i in
            app)
                SERVICE='APP'
                ;;
            db)
                SERVICE='DB'
                ;;
            webserver)
                SERVICE='WEBSERVER'
        esac

        local REPOSITORY_URI=''
        REPOSITORY_URI=$(grep "${SERVICE}_REPOSITORY_URI" $DATAFILE \
            | awk '{ print $2 }')

        sed -i "s#<REPOSITORY_URI>#${REPOSITORY_URI}#" \
            ecs/tasks/$i-task.json

        sed -i "#executionRoleArn# s#: .*# :\"${ECS_TASK_ROLE_ARN}\",#" \
            ecs/tasks/$i-task.json

        if [[ $i = 'db' ]]; then
            ## Update the task definition for the db to consume this EFS
            sed -i "s/<FILESYSTEMID>/${FILESYSTEMID}/g" \
                ecs/tasks/db-task.json
        fi

        # register the task definition
        aws ecs register-task-definition \
            --cli-input-json file://ecs/tasks/"${i}"-task.json
    done

    ## TODO: WIP
    # Update the task definition for code deploy
    #for i in {app,db,webserver}; do
    #    sed -i "/image/s/$i/<IMAGE1_NAME>/" ecs/tasks/"$i"-task.json
    #done

}

create_codeBuildServiceRole () {

    aws iam create-role \
        --role-name CodeBuildServiceRole \
        --assume-role-policy-document file://codeBuild/create-role.json

    aws iam put-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-name CodeBuildServiceRolePolicy \
        --policy-document file://codeBuild/create-role-policy.json

    # Add secrets manager permissions to code build role
    aws iam attach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

    # Add ECR permissions to the code build role
    aws iam attach-role-policy \
        --role-name CodeBuildServiceRole \
        --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds

    # Give the permissions time to apply
    sleep 20

}

create_codeBuildProject () {

    ## Populate the project.json from the project.json.tmpl
    sed "s/<PROJECT>/${PROJECT}/g" codeBuild/project.json.tmpl \
        > codeBuild/project.json

    sed -i "s/<REGION>/${REGION}/g" codeBuild/project.json
    sed -i "s/<ACCOUNT>/${ACCOUNT}/g" codeBuild/project.json

    aws codebuild create-project \
        --cli-input-json file://codeBuild/project.json

    ## Run the build to populate the ECR repos
    aws codebuild start-build \
        --project-name "$PROJECT" \
        --buildspec-override buildspec-full.yml

}

create_codePipelineServiceRole () {

    ## Populate the .json from the .json.tmpl
    sed "s/<ACCOUNT>/${ACCOUNT}/g" \
        codePipeline/create-role-policy.json.tmpl \
        > codePipeline/create-role-policy.json

    sed -i "s/<PROJECT>/${PROJECT}/g" \
        codePipeline/create-role-policy.json

    aws iam create-role \
        --role-name CodePipelineServiceRole \
        --assume-role-policy-document file://codePipeline/create-role.json

    aws iam attach-role-policy \
        --role-name CodePipelineServiceRole \
        --policy-arn arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess

    # Add codestar permissions to code pipeline service role
    aws iam put-role-policy \
        --role-name CodePipelineServiceRole \
        --policy-name CodePipelineServiceRolePolicy \
        --policy-document file://codePipeline/create-role-policy.json

}

create_loadbalancers () {

    ## Need two load balancers, one internal and one internet facing.
    ## Public facing load balancer resolves traffic on port 80 to the
    ## webserver.
    ## Private facing load balancer resolves traffic on port 3306 to the
    ## mysqldb and traffic on 9000 to the php app server.

    ## Requires two target groups for each of the services
    ## {app,db,webservice} in order to facilitate the code deploy
    ## deployments for each component.\

    ## Listeners for the private load balancer endpoints (3306 and 9000)
    ## require private DNS resolution (app.local, db.local)

    create_load_balancer() {
        if [[ $# -ne 1 ]]; then
            echo "Must pass in internal/internet-facing"
            exit 255
        fi

        local TYPE=''
        local SCHEME=''
        local LOADBALANCER_ARN=''
        if [[ $1 == 'internal' ]]; then
            SCHEME='internal'
            TYPE='network'

            LOADBALANCER_ARN=$(aws elbv2 create-load-balancer \
                --name "$PROJECT"-${TYPE}-alb \
                --scheme $SCHEME \
                --type $TYPE \
                --subnet-mapping SubnetId="$SUBNETID0" SubnetId="$SUBNETID1" \
                --ip-address-type ipv4 \
                | grep 'LoadBalancerArn' | awk '{ print $2 }')

        else
            SCHEME='internet-facing'
            TYPE='application'

            LOADBALANCER_ARN=$(aws elbv2 create-load-balancer \
                --name "$PROJECT"-${TYPE}-alb \
                --scheme $SCHEME \
                --type $TYPE \
                --subnets "$SUBNETID0" "$SUBNETID1" \
                --security-groups "$SECURITYGROUPID" \
                --ip-address-type ipv4 \
                | grep 'LoadBalancerArn' | awk '{ print $2 }')

        fi

        echo $LOADBALANCER_ARN
    }

    create_target_group () {
        if [[ $# -ne 4 ]]; then
            echo "Must pass in service, blue/green, protocol, and port"
            exit 255
        fi

        local SERVICE=$1
        local COLOR=$2
        local PROTOCOL=$3
        local PORT=$4

        local TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$PROJECT"-${SERVICE}-tg-${COLOR} \
        --protocol $PROTOCOL \
        --port $PORT \
        --vpc-id "$VPCID" \
        --health-check-protocol $PROTOCOL \
        --health-check-port $PORT \
        --target-type ip \
        | grep 'TargetGroupArn' \
        | awk '{ print $2 }')

        echo $TARGET_GROUP_ARN

    }

    create_listener () {

        if [[ $# -ne 4 ]]; then
            echo "Must pass in LOAD_BALANCER_ARN, TG_ARN, PROTOCOL, and PORT"
        fi

        local LOAD_BALANCER_ARN=$1
        local TG_ARN=$2
        local PROTOCOL=$3
        local PORT=$4

        local LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$LOAD_BALANCER_ARN" \
        --protocol $PROTOCOL \
        --port $PORT \
        --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
        | grep 'ListenerArn' \
        | awk '{ print $2 }')

        echo $LISTENER_ARN
    }

    INTERNET_LOADBALANCER_ARN=$(create_load_balancer 'internet')

    echo "INTERNET_LOADBALANCER_ARN $INTERNET_LOADBALANCER_ARN" >> $DATAFILE

    WEB_TARGETGROUP_BLUE_ARN=$(create_target_group 'web' 'blue' 'HTTP' 80)

    echo "WEB_TARGETGROUP_BLUE_ARN $WEB_TARGETGROUP_BLUE_ARN" >> $DATAFILE

    WEB_TARGETGROUP_GREEN_ARN=$(create_target_group 'web' 'green' 'HTTP' 80)

    echo "WEB_TARGETGROUP_GREEN_ARN $WEB_TARGETGROUP_GREEN_ARN" >> $DATAFILE

    WEB_LISTENER_ARN=$(create_listener "$INTERNET_LOADBALANCER_ARN" \
        "$WEB_TARGETGROUP_BLUE_ARN" 'HTTP' 80)

    echo "WEB_LISTENER_ARN $WEB_LISTENER_ARN" >> $DATAFILE

    INTERNAL_LOADBALANCER_ARN=$(create_load_balancer 'internal')

    echo "INTERNAL_LOADBALANCER_ARN $INTERNAL_LOADBALANCER_ARN" >> $DATAFILE

    DB_TARGETGROUP_BLUE_ARN=$(create_target_group 'db' 'blue' 'TCP' 3306)

    echo "DB_TARGETGROUP_BLUE_ARN $DB_TARGETGROUP_BLUE_ARN" >> $DATAFILE

    DB_TARGETGROUP_GREEN_ARN=$(create_target_group 'db' 'green' 'TCP' 3306)

    echo "DB_TARGETGROUP_GREEN_ARN $DB_TARGETGROUP_GREEN_ARN" >> $DATAFILE

    DB_LISTENER_ARN=$(create_listener "$INTERNAL_LOADBALANCER_ARN" \
        "$DB_TARGETGROUP_BLUE_ARN" 'TCP' 3306)

    echo "DB_LISTENER_ARN $DB_LISTENER_ARN" >> $DATAFILE

    APP_TARGETGROUP_BLUE_ARN=$(create_target_group 'app' 'blue' 'TCP' 9000)

    echo "APP_TARGETGROUP_BLUE_ARN $APP_TARGETGROUP_BLUE_ARN" >> $DATAFILE

    APP_TARGETGROUP_GREEN_ARN=$(create_target_group 'app' 'green' 'TCP' 9000)

    echo "APP_TARGETGROUP_GREEN_ARN $APP_TARGETGROUP_GREEN_ARN" >> $DATAFILE

    APP_LISTENER_ARN=$(create_listener "$INTERNAL_LOADBALANCER_ARN" \
        "$APP_TARGETGROUP_BLUE_ARN" 'TCP' 9000)

    echo "APP_LISTENER_ARN $APP_LISTENER_ARN" >> $DATAFILE

}

create_ecsServices () {

    for i in {app,db,webserver}; do
        local TASKDEFINITION=$(aws ecs list-task-definitions \
            --family-prefix laravel-$i \
            --status ACTIVE \
            --sort DESC \
            --max-items 1 \
            | grep 'arn' \
            | awk -F '/' '{ print $2 }')

        sed "s/<TASKDEFINITION>/$TASKDEFINITION/" \
            ecs/services/create-"$i"-service.json.tmpl \
            > ecs/services/create-"$i"-service.json

        sed -i "s/<CLUSTERNAME>/$CLUSTERNAME/" \
            ecs/services/create-"$i"-service.json

        local SERVICENAME="${PROJECT}-${i}-service"
        sed -i "s/<SERVICENAME>/$SERVICENAME/" \
            ecs/services/create-"$i"-service.json

        # TODO
        # WIP
        local SERVICE_ID=$(aws servicediscovery \
            create-service --name $i \
            --dns-config NamespaceId="${NAMESPACEID}",DnsRecords='[{Type="A",TTL="60"}]' \
            --health-check-custom-config FailureThreshold=1 --region $REGION \
            | grep ' Id:' \
            | awk '{print $2 }')

        case $i in
            app)
                echo "APP_SERVICE_ID ${SERVICE_ID}" >> $DATAFILE
                ;;
            db)
                echo "DB_SERVICE_ID ${SERVICE_ID}" >> $DATAFILE
                ;;
            webserver)
                echo "WEBSERVER_SERVICE_ID ${SERVICE_ID}" >> $DATAFILE
                ;;
        esac

        local REGISTRY_ARN=$(aws servicediscovery \
            get-service --id $SERVICE_ID \
            | grep 'Arn' \
            | awk '{ print $2 }')


        sed -i "s#<REGISTRY_ARN>#${REGISTRY_ARN}#" \
            ecs/services/create-"$i"-service.json

        local TARGETGROUPARN=''
        case $i in
            app)
                TARGETGROUPARN=$APP_TARGETGROUP_BLUE_ARN
                ;;
            db)
                TARGETGROUPARN=$DB_TARGETGROUP_BLUE_ARN
                ;;
            webserver)
                TARGETGROUPARN=$WEB_TARGETGROUP_BLUE_ARN
                ;;
        esac

        sed -i "s#<TARGETGROUPARN>#$TARGETGROUPARN#" \
            ecs/services/create-"$i"-service.json

        sed -i "s/<CONTAINERNAME>/${PROJECT}-${i}/" \
            ecs/services/create-"$i"-service.json
        sed -i "s/<SECURITYGROUPID>/$SECURITYGROUPID/" \
            ecs/services/create-"$i"-service.json
        sed -i "s/<SUBNETID0>/$SUBNETID0/" \
            ecs/services/create-"$i"-service.json
        sed -i "s/<SUBNETID1>/$SUBNETID1/" \
            ecs/services/create-"$i"-service.json

        aws ecs create-service \
            --service-name "$i"-service \
            --cli-input-json file://ecs/services/create-"$i"-service.json

    done

    # Give the services time to fully register
    sleep 20
}

create_codePipeline () {

    ## Populate the create-pipeline.json from the create-pipeline.json.tmpl
    sed "s/<ACCOUNT>/$ACCOUNT/g" \
        codePipeline/create-pipeline.json.tmpl \
        > codePipeline/create-pipeline.json
    sed -i "s/<PROJECT>/$PROJECT/g" \
        codePipeline/create-pipeline.json

    ## Determine Codestar integration
    CONNECTIONARN=$(aws codestar-connections \
        list-connections \
        | grep 'ConnectionArn' \
        | awk '{ print $2 }')

    sed -i "s#<CONNECTIONARN>#$CONNECTIONARN#g" codePipeline/create-pipeline.json

    # Create the codePipeline
    aws codepipeline create-pipeline \
        --cli-input-json file://codePipeline/create-pipeline.json

}

create_codeDeployServiceRole () {
    ## TODO - WIP
    aws iam create-role --role-name CodeDeployServiceRole \
        --assume-role-policy-document file://codeDeploy/create-role.json

    aws iam attach-role-policy --role-name CodeDeployServiceRole \
        --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS

}

main () {
    init
    create_vpc
    create_ecrRepos
    create_cloudWatchLogGroups
    create_artifactS3Bucket
    create_efs
    create_ecsCluster
    create_ecsTaskExecutionRole
    create_ecsTaskRegistrations
    create_codeBuildServiceRole
    create_codeBuildProject
    create_codePipelineServiceRole
    create_loadbalancers
    create_ecsServices
    # TODO create_codePipeline
    # TODO create_codeDeployServiceRole
    # TODO Create Code Deploy build

    echo "--==SUCCESS==--"
}

main
