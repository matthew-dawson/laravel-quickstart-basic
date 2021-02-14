#! /bin/bash

PROJECT=laravel

aws ecs delete-cluster --cluster "$PROJECT"-cluster
