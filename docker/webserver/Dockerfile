FROM nginx:alpine

RUN set -eux

COPY --chown=nginx:nginx ./src/public/ /var/www/public/
COPY ./docker/webserver/conf/ /etc/nginx/conf.d/
RUN rm /etc/nginx/conf.d/default.conf
COPY ./docker/webserver/docker-entrypoint.d/ /docker-entrypoint.d/

ENTRYPOINT [ "/docker-entrypoint.sh" ]

EXPOSE 80

STOPSIGNAL SIGQUIT
CMD [ "nginx", "-g", "daemon off;" ]
