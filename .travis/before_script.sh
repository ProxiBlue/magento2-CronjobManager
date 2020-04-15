#!/usr/bin/env bash

set -e
trap '>&2 echo Error: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?' ERR

# mock mail
sudo service postfix stop
echo # print a newline
smtp-sink -d "%d.%H.%M.%S" localhost:2500 1000 &
echo 'sendmail_path = "/usr/sbin/sendmail -t -i "' > ~/.phpenv/versions/$(phpenv version-name)/etc/conf.d/sendmail.ini

# disable xdebug and adjust memory limit
test "$TEST_SUITE" = "coverage" || echo > ~/.phpenv/versions/$(phpenv version-name)/etc/conf.d/xdebug.ini
echo 'memory_limit = -1' >> ~/.phpenv/versions/$(phpenv version-name)/etc/conf.d/travis.ini
phpenv rehash;

composer selfupdate

# clone main magento github repository
git clone --branch $MAGENTO_VERSION --depth=1 https://github.com/magento/magento2

# install Magento
cd magento2

# add composer package under test, composer require will trigger update/install
MY_REPO_SLUG=${TRAVIS_PULL_REQUEST_SLUG:-$TRAVIS_REPO_SLUG}
MY_BRANCH=${TRAVIS_PULL_REQUEST_BRANCH:-$TRAVIS_BRANCH}
composer config minimum-stability dev
composer config repositories.travis_to_test git https://github.com/${MY_REPO_SLUG}.git
case $MY_BRANCH in
    "1.x" | "0.x")
        composer require ${COMPOSER_PACKAGE_NAME}:${MY_BRANCH}-dev\#{$TRAVIS_COMMIT}
        ;;
    *)
        composer require ${COMPOSER_PACKAGE_NAME}:dev-${MY_BRANCH}\#{$TRAVIS_COMMIT}
        ;;
esac

# prepare for test suite
cp vendor/$COMPOSER_PACKAGE_NAME/Test/Integration/phpunit.xml.dist dev/tests/integration/phpunit.xml
cp vendor/$COMPOSER_PACKAGE_NAME/Test/Unit/phpunit.xml.dist dev/tests/unit/phpunit.xml
case $TEST_SUITE in
    integration|coverage)
        cd dev/tests/integration

        # create database and move db config into place
        mysql -uroot -e '
            SET @@global.sql_mode = NO_ENGINE_SUBSTITUTION;
            CREATE DATABASE magento_integration_tests;
        '
        cp etc/install-config-mysql.travis.php.dist etc/install-config-mysql.php
        sed -i '/amqp/d' etc/install-config-mysql.php

        cd ../../..
        ;;
esac

if test "$TEST_SUITE" = "coverage"; then
    composer require --dev --no-interaction php-coveralls/php-coveralls
fi
