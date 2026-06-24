#!/bin/sh
set -e

if [ "$1" = 'frankenphp' ] || [ "$1" = 'php' ] || [ "$1" = 'bin/console' ]; then
	###> dunglas/symfony-docker ###
	# Install the project the first time PHP is started
	# This block will remove itself after the installation
	if [ "$(cat composer.json)" = '{}' ]; then
		rm -Rf tmp/
		composer create-project "symfony/skeleton $SYMFONY_VERSION" tmp --stability="$STABILITY" --prefer-dist --no-progress --no-interaction --no-install

		cd tmp
		cp -Rp . ..
		cd -
		rm -Rf tmp/

		composer require "php:>=$PHP_VERSION"
		composer config --json extra.symfony.docker 'true'

		# Remove the project install block from this script and the compose.yaml
		sed -i '/^\t###> dunglas\/symfony-docker ###/,/^\t###< dunglas\/symfony-docker ###/d' frankenphp/docker-entrypoint.sh
		sed -i '/###> dunglas\/symfony-docker ###/,/###< dunglas\/symfony-docker ###/d' compose.yaml
	fi
	###< dunglas/symfony-docker ###

	if [ -z "$(ls -A 'vendor/' 2>/dev/null)" ]; then
		composer install --prefer-dist --no-progress --no-interaction
	fi

	# Display information about the current project
	# Or about an error in project initialization
	php bin/console -V

	echo 'PHP app ready!'
fi

exec docker-php-entrypoint "$@"
