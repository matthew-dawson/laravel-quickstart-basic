#! /bin/bash

set -eux


## Detach policies first
aws iam detach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam delete-role \
    --role-name ecsTaskExecutionRole
