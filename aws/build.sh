#! /bin/bash

# Determine AWS account
ACCOUNT=$(aws sts get-caller-identity \
    | grep 'Account' | awk '{ print $2 }' \
    | tr -d ',"')
echo "$ACCOUNT" > account.data

## Update accountId in various places
#for FILENAME in {tasks/webserver-task.json,\
#    tasks/db-task.json,\
#    tasks/app-task.json}; do
#    sed -i "/image/s/ \".*.dkr/\ "$ACCOUNT.dkr/" "$FILENAME"
#done

## TODO Populate the docker credentials within secrets manager

# Create VPC
./create_vpc.sh

# Create ECR repositories
./create_ecrRepos.sh

# TODO Create CodeDeploy build
./create_codeDeploy.sh

# TODO Build the images

#### TODO Create load balancer

# Create ECS Cluster
./create_ecsCluster.sh

## TODO NICE TO HAVE
# Create EFS
./create_efs.sh

# Create ecsTaskExecutionRole
./create_ecsTaskExecutionRole.sh

# Register task definition
./create_ecsTaskRegistrations.sh

# TODO Create ECS service

# TODO Create Code Pipeline


# TODO Delete Code Pipeline

# TODO Delete ECS Services

# TODO Delete deregister task definitions

# Delete EFS
./delete_efs.sh

# Delete ecsTaskExecutionRole
./delete_ecsTaskExecutionRole.sh

# Delete ECS Cluster
./delete_ecsCluster.sh

### TODO Delete Load Balancer

# TODO Delete CodeDeploy build

# Delete ECR repositories
./delete_ecrRepos.sh

# Delete VPC
./delete_vpc.sh

## TODO Remove docker credentials from secrets manager
