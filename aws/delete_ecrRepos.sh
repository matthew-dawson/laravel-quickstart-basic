#! /bin/bash

set -eux

for i in {app,db,webserver}; do
    aws ecr delete-repository \
    --repository-name "laravel/$i" \
    --force
done
