#! /bin/bash

set -eux

aws iam delete-role --role-name ecsTaskExecutionRole
