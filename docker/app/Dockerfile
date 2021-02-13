FROM php:7.2-fpm

RUN set -eux

RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    locales \
    zip \
    jpegoptim optipng pngquant gifsicle \
    vim \
    unzip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install extensions
RUN docker-php-ext-install pdo_mysql mbstring zip exif pcntl \
    && docker-php-ext-configure gd --with-gd --with-freetype-dir=/usr/include \
    --with-jpeg-dir=/usr/include --with-png-dir=/usr/include \
    && docker-php-ext-install gd

# Install composer
RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

# Create user
RUN addgroup --gid 1000 www \
    && adduser --disabled-password --gecos "" -uid 1000 --gid 1000 www \
    && chown -R www:www /var/www/

COPY --chown=www:www ./src/ /var/www/
COPY ./docker/app/docker-entrypoint.sh /
USER www

WORKDIR /var/www/
RUN php /usr/local/bin/composer install

ENTRYPOINT [ "/docker-entrypoint.sh" ]
STOPSIGNAL SIGQUIT

EXPOSE 9000

CMD [ "php-fpm" ]
