#! /bin/bash

set -eux

ROLENAME=ecsTaskExecutionRole
ROLEARN=$(aws iam create-role \
    --region eu-west-2 \
    --role-name $ROLENAME \
    --assume-role-policy-document file://task-execution-assume-role.json \
    | grep 'Arn' \
    | awk '{ print $2 }' \
    | tr -d ',"' )

for i in {app,db,webserver}; do 
    sed -i "#executionRoleArn# s#: .*# :\"$ROLEARN\",#" tasks/$i-task.json
done

# Attach the role policy to the role
aws iam attach-role-policy \
    --region eu-west-2 \
    --role-name $ROLENAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
