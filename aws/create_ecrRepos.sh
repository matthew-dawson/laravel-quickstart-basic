#! /bin/bash

set -eux

PROJECT=laravel

for i in {app,db,webserver}; do
    REPOSITORYUI=$(aws ecr create-repository \
    --repository-name "$PROJECT/$i" \
    --image-scanning-configuration scanOnPush=false \
    --region eu-west-2 \
    | grep 'repositoryUri' \
    | awk '{ print $2 }' \
    | tr -d ',"')

    sed -i "#image# s#: .*# :\"$REPOSITORYUI\",#" tasks/$i-task.json
done

