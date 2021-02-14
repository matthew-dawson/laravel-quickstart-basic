#! /bin/bash

set -eux

for i in {app,db,webserver}; do
    aws logs create-log-group \
        --log-group-name /ecs/laravel-$i
done
