#!/bin/sh
set -e

# Generate .env from container environment if APP_KEY is set and .env is empty
if [ ! -s .env ] || [ ! -f .env ]; then
    echo "[entrypoint] Generating .env from environment..."
    cat > .env <<EOF
APP_NAME="${APP_NAME:-Invoice Ninja}"
APP_ENV="${APP_ENV:-production}"
APP_KEY="${APP_KEY:-}"
APP_DEBUG="${APP_DEBUG:-false}"
APP_URL="${APP_URL:-http://localhost}"
APP_ENV="${APP_ENV:-production}"

DB_CONNECTION="${DB_CONNECTION:-mysql}"
DB_HOST="${DB_HOST:-${DB_HOSTNAME:-${DATABASE_HOST:-localhost}}}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-${DATABASE_NAME:-ninja}}"
DB_USERNAME="${DB_USERNAME:-${DATABASE_USERNAME:-ninja}}"
DB_PASSWORD="${DB_PASSWORD:-${DATABASE_PASSWORD:-ninja}}"

REQUIRE_HTTPS="${REQUIRE_HTTPS:-false}"
TRUSTED_PROXIES="${TRUSTED_PROXIES:-*}"
LOG_CHANNEL="${LOG_CHANNEL:-stack}"
CACHE_DRIVER="${CACHE_DRIVER:-file}"
SESSION_DRIVER="${SESSION_DRIVER:-file}"
QUEUE_CONNECTION="${QUEUE_CONNECTION:-sync}"

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PASSWORD="${REDIS_PASSWORD:-null}"
REDIS_PORT="${REDIS_PORT:-6379}"
EOF
    echo "[entrypoint] .env generated"
fi

# Ensure storage and cache are writable
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

# Run artisan commands
php artisan config:cache 2>/dev/null || true
php artisan route:cache 2>/dev/null || true
php artisan view:cache 2>/dev/null || true

# Create storage symlink if missing
php artisan storage:link 2>/dev/null || true

exec "$@"
