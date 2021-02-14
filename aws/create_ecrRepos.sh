#! /bin/bash

set -eux

for i in {app,db,webserver}; do
    aws ecr create-repository \
    --repository-name "laravel/$i" \
    --image-scanning-configuration scanOnPush=false \
    --region eu-west-2
done

