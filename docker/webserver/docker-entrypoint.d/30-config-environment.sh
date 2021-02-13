#! /bin/sh

set -eux

if [ "$ENVIRONMENT" = "production" ] ; then
    sed -i '/fastcgi_pass/s/app/app.local/' /etc/nginx/conf.d/app.conf
fi
