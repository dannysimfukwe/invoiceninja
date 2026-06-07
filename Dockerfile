FROM php:8.3-fpm-alpine

# Install system deps + PHP extensions
RUN apk add --no-cache \
    nginx supervisor libpng-dev libjpeg-turbo-dev freetype-dev \
    libzip-dev icu-dev oniguruma-dev libxml2-dev \
    nodejs npm git \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql mbstring xml bcmath zip gd intl opcache soap \
    && pecl install redis && docker-php-ext-enable redis \
    && rm -rf /var/cache/apk/*

# PHP tuning
RUN echo "upload_max_filesize = 100M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_execution_time = 600" >> /usr/local/etc/php/conf.d/upload.ini

# Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy app
COPY . .

# Install composer deps (no dev, optimized)
RUN if [ -f composer.json ]; then \
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts; \
    fi

# App key generation + storage link handled by entrypoint

# Nginx config
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Permissions
RUN mkdir -p storage/framework/{cache,sessions,testing,views} \
    bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sh", "-c", "php-fpm && nginx -g 'daemon off;'"]
