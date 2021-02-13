FROM mysql:5.7.22

RUN set -eux

COPY ./docker/db/conf/* /etc/mysql/conf.d/
COPY ./docker/db/sql/* /docker-entrypoint-initdb.d/

ENTRYPOINT [ "docker-entrypoint.sh" ]

EXPOSE 3306 33060

CMD [ "mysqld" ]
