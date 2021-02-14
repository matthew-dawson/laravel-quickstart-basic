#! /bin/bash

set -eux
## Create task definitions
aws ecs register-task-definition --cli-input-json file://tasks/app-task.json
aws ecs register-task-definition --cli-input-json file://tasks/webserver-task.json
aws ecs register-task-definition --cli-input-json file://tasks/db-task.json
