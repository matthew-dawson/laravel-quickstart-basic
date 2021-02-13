#! /bin/bash

set -eux

php artisan migrate --force \
    && php-fpm
