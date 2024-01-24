#!/usr/bin/env sh

set -e
set -x

database_host=$(trurl $DATABASE_URL --get '{host}')
database_port=$(trurl $DATABASE_URL --get '{port}')

try=0
if [[ $MYSQL_WAIT_SECONDS != 0 ]]; then
  until nc -z -v -w30 $database_host ${database_port:-3306}
  do
    echo "Waiting for database connection..."
    # wait for 5 seconds before check again
    sleep 1

    try=$((try+1))

    if [[ $try -gt $MYSQL_WAIT_SECONDS ]]; then
      echo "Error: We have been waiting for database connection too long already; failing."
      exit 1
    fi
  done
fi

console() {
  php -derror_reporting=E_ALL bin/console "$@"
}

update_all_plugins() {
  list_with_updates=$(php bin/console plugin:list --json | jq 'map(select(.upgradeVersion != null)) | .[].name' -r)

  for plugin in $list_with_updates; do
    php -derror_reporting=E_ALL bin/console plugin:update $plugin
  done
}

install_all_plugins() {
  list_with_updates=$(php bin/console plugin:list --json | jq 'map(select(.installedAt == null)) | .[].name' -r)

  for plugin in $list_with_updates; do
    php -derror_reporting=E_ALL bin/console plugin:install --activate $plugin
  done
}

if php bin/console system:config:get shopware.installed; then
  php -derror_reporting=E_ALL bin/console system:update:finish
  php -derror_reporting=E_ALL bin/console plugin:refresh

  update_all_plugins
  install_all_plugins
  php -derror_reporting=E_ALL bin/console theme:compile
else
  # Shopware is not installed
  php -derror_reporting=E_ALL bin/console system:install --create-database "--shop-locale=$INSTALL_LOCALE" "--shop-currency=$INSTALL_CURRENCY" --force
  php -derror_reporting=E_ALL bin/console user:create "$INSTALL_ADMIN_USERNAME" --admin --password="$INSTALL_ADMIN_PASSWORD" -n
  php -derror_reporting=E_ALL bin/console sales-channel:create:storefront --name=Storefront --url="$APP_URL"
  php -derror_reporting=E_ALL bin/console theme:change --all Storefront
  php -derror_reporting=E_ALL bin/console system:config:set core.frw.completedAt '2019-10-07T10:46:23+00:00'
  php -derror_reporting=E_ALL bin/console system:config:set core.usageData.shareUsageData false --json
  php -derror_reporting=E_ALL bin/console plugin:refresh

  install_all_plugins
fi
