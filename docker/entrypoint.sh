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
    chown www-data:www-data .env 2>/dev/null || true
fi

# Ensure storage, cache, and .env are writable by www-data
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true
chown www-data:www-data .env 2>/dev/null || true
chmod 664 .env 2>/dev/null || true

# Add SNAPPDF_CHROMIUM_PATH to .env if missing (needed for Snappdf PDF generation)
if [ -f .env ] && ! grep -q "^SNAPPDF_CHROMIUM_PATH=" .env; then
    echo "SNAPPDF_CHROMIUM_PATH=/usr/bin/chromium" >> .env
    echo "SNAPPDF_CHROMIUM_ARGUMENTS=\"--no-sandbox --disable-setuid-sandbox\"" >> .env
    echo "[entrypoint] Added SNAPPDF_CHROMIUM_PATH and SNAPPDF_CHROMIUM_ARGUMENTS to .env"
fi

# Auto-deploy React UI if head.blade.php is empty (not bundled in self-hosted tarball)
if [ -f resources/views/react/head.blade.php ] && [ ! -s resources/views/react/head.blade.php ]; then
    echo "[entrypoint] React head.blade.php is empty, downloading React UI..."

    # Find latest React UI release from GitHub
    REACT_VERSION=$(curl -sL "https://api.github.com/repos/invoiceninja/ui/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*: "//;s/".*//')

    if [ -n "$REACT_VERSION" ]; then
        echo "[entrypoint] Downloading React UI release $REACT_VERSION..."
        curl -sL "https://github.com/invoiceninja/ui/releases/download/$REACT_VERSION/invoiceninja-react.zip" -o /tmp/react.zip 2>/dev/null

        if [ -f /tmp/react.zip ] && [ -s /tmp/react.zip ]; then
            echo "[entrypoint] Extracting React UI..."
            rm -rf /tmp/react_extract
            mkdir -p /tmp/react_extract
            unzip -o /tmp/react.zip -d /tmp/react_extract 2>/dev/null

            if [ -d /tmp/react_extract/dist ]; then
                # Copy React assets to public/
                cp -r /tmp/react_extract/dist/react public/ 2>/dev/null || true
                cp -r /tmp/react_extract/dist/rsms public/ 2>/dev/null || true
                cp /tmp/react_extract/dist/logo180.png public/ 2>/dev/null || true
                cp /tmp/react_extract/dist/favicon.ico public/ 2>/dev/null || true
                cp /tmp/react_extract/dist/robots.txt public/ 2>/dev/null || true
                cp /tmp/react_extract/dist/manifest.json public/ 2>/dev/null || true
                cp -r /tmp/react_extract/dist/docuninja public/ 2>/dev/null || true
                cp -r /tmp/react_extract/dist/gateway-card-images public/ 2>/dev/null || true
                cp -r /tmp/react_extract/dist/dap-logos public/ 2>/dev/null || true
                cp -r /tmp/react_extract/dist/tinymce_6.4.2 public/ 2>/dev/null || true

                # Generate head.blade.php from dist/index.html <head> content
                sed -n '/<head>/,/<\/head>/p' /tmp/react_extract/dist/index.html | sed '1d;$d' > resources/views/react/head.blade.php

                # Fix ownership
                chown -R www-data:www-data public/react public/rsms 2>/dev/null || true

                # Enable React mode
                php artisan tinker --execute="DB::table('accounts')->update(['set_react_as_default_ap' => 1]);" 2>/dev/null || true

                echo "[entrypoint] React UI deployed and enabled successfully"
            else
                echo "[entrypoint] React dist/ not found in zip, falling back to Flutter mode"
                php artisan tinker --execute="DB::table('accounts')->where('set_react_as_default_ap', 1)->update(['set_react_as_default_ap' => 0]);" 2>/dev/null || true
            fi

            # Cleanup
            rm -rf /tmp/react.zip /tmp/react_extract
        else
            echo "[entrypoint] Failed to download React UI, falling back to Flutter mode"
            php artisan tinker --execute="DB::table('accounts')->where('set_react_as_default_ap', 1)->update(['set_react_as_default_ap' => 0]);" 2>/dev/null || true
        fi
    else
        echo "[entrypoint] Could not determine React UI version, falling back to Flutter mode"
        php artisan tinker --execute="DB::table('accounts')->where('set_react_as_default_ap', 1)->update(['set_react_as_default_ap' => 0]);" 2>/dev/null || true
    fi
fi

# Run artisan commands (clear stale cache first - setup may have changed .env)
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan view:clear 2>/dev/null || true
php artisan config:cache 2>/dev/null || true
php artisan route:cache 2>/dev/null || true

# Create storage symlink if missing
php artisan storage:link 2>/dev/null || true

exec "$@"
