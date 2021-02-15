#! /bin/bash

set -ex

if [ -z "${ENVIRONMENT}" ]; then
    php /usr/local/bin/composer install
fi

php artisan migrate --force \
    && php-fpm
