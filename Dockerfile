FROM php:8.3-fpm

# Install system deps + PHP extensions + Chromium for Snappdf PDF generation
RUN apt-get update && apt-get install -y \
    nginx supervisor libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libzip-dev libicu-dev libonig-dev libxml2-dev libgmp-dev \
    nodejs npm git default-mysql-client curl unzip \
    autoconf g++ make pkg-config \
    chromium \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gmp pdo_mysql mbstring xml bcmath zip gd intl opcache soap \
    && pecl install redis && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*

# PHP tuning + HOME for Chromium/Snappdf
RUN echo "upload_max_filesize = 100M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/upload.ini \
    && echo "max_execution_time = 600" >> /usr/local/etc/php/conf.d/upload.ini

# Set HOME for php-fpm workers (needed by Chromium for crashpad database)
RUN echo "env[HOME] = /tmp" > /usr/local/etc/php-fpm.d/z-home.conf

# Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy app
COPY . .

# Install composer deps (no dev, optimized)
RUN if [ -f composer.json ]; then \
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts; \
    fi

# Nginx config
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/sites-enabled/default 2>/dev/null; \
    sed -i '/include.*sites-enabled/d' /etc/nginx/nginx.conf 2>/dev/null; \
    true

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Permissions
RUN mkdir -p storage/framework/{cache,sessions,testing,views} \
    bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap

# HOME for Chromium/Snappdf (needs writable crashpad directory)
ENV HOME=/tmp

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sh", "-c", "php-fpm -D && nginx -g 'daemon off;'"]
