#!/usr/bin/env bash
set -e

#This script starts a set of containers to manage a php environment
PROJECT_DIR_NAME=$1
GIT_PROJECT=$2 #"git@bitbucket.org:.git"
MYSQL_ROOT_PASSWORD=${3:-root_password}
MYSQL_DATABASE=${4:-database_name}
MYSQL_USER=${5:-username}
MYSQL_PASSWORD=${6:-password}
NETWORK_NAME="network_name"
DATA_CONTAINER_NAME="data_cont"
NGINX_CONTAINER_NAME="nginx_cont"
FPM_CONTAINER_NAME="fpm_cont"
DB_CONTAINER_NAME="db_cont"


if [ "$(id -u)" != "0" ]; then
    echo "You don't have sufficient privileges to run this script. Try with sudo if you can!!!"
    exit 1
fi

if [ -z "$1"  ]
then
    echo "No arguments supplied."
    echo "$0 <PROJECT_DIR_NAME> <GIT_PROJECT> are required arguments"
    echo "[MYSQL_ROOT_PASSWORD] [MYSQL_DATABASE] [MYSQL_USER MYSQL_PASSWORD] are optional arguments"
    exit 1
fi
set -xeu
containers=($NGINX_CONTAINER_NAME $FPM_CONTAINER_NAME $DB_CONTAINER_NAME $DATA_CONTAINER_NAME)
for container in "${containers[@]}"
do
    if [[ ! -z "$( docker ps -a | grep $container )" ]]; then
	docker rm -vf $container
    fi
done

if [[ -z "$( docker network ls | grep $NETWORK_NAME )" ]]; then
    docker network create --driver bridge $NETWORK_NAME
fi

if [[ -z "$( docker ps -a | grep $DATA_CONTAINER_NAME )" ]]; then
    docker create -v /data --name $DATA_CONTAINER_NAME --net $NETWORK_NAME debian:jessie /bin/true
    docker run --rm -it --volumes-from $DATA_CONTAINER_NAME --net $NETWORK_NAME -v ~/.ssh:/root/.ssh debian:jessie bash -c "apt-get update && apt-get install -y git && cd /data && git clone $GIT_PROJECT"
fi

if [[ -z "$( docker ps -a | grep $NGINX_CONTAINER_NAME )" ]]; then
    docker run -d --name $NGINX_CONTAINER_NAME --volumes-from $DATA_CONTAINER_NAME --net $NETWORK_NAME -p 80:80 nginx
    #the following command should be part of the git project we are going to clone
    docker exec $NGINX_CONTAINER_NAME bash -c "ln -s /data/${PROJECT_DIR_NAME}/custom_nginx.conf /etc/nginx/conf.d/"
else
    docker start $NGINX_CONTAINER_NAME 
fi

if [[ -z "$( docker ps -a | grep $FPM_CONTAINER_NAME )" ]]; then
    docker run -d --name $FPM_CONTAINER_NAME --volumes-from $DATA_CONTAINER_NAME --net $NETWORK_NAME php:5.5-fpm
    #the following command should be part of the git project we are going to clone
    docker exec $FPM_CONTAINER_NAME bash -c "cd /data/${PROJECT_DIR_NAME}/www && chmod -R 775 . && chown -R www-data:www-data . &&  docker-php-ext-configure mysqli && docker-php-ext-install mysqli && ln -s /data/${PROJECT_DIR_NAME}/php.ini /usr/local/etc/php/ && apt-get update && apt-get install -y php5-imap libc-client2007e-dev && php5enmod imap && mkdir -p /usr/kerberos && ln -s /usr/lib/x86_64-linux-gnu/mit-krb5/ /usr/kerberos/lib && docker-php-ext-configure imap --with-kerberos --with-imap-ssl && docker-php-ext-install imap"
else
    docker start $FPM_CONTAINER_NAME
fi

if [[ -z "$( docker ps -a | grep $FPM_CONTAINER_NAME )" ]]; then
    docker run -d --name $DB_CONTAINER_NAME --volumes-from $DATA_CONTAINER_NAME --net $NETWORK_NAME -e MYSQL_DATABASE=$MYSQL_DATABASE -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD -e MYSQL_USER=$MYSQL_USER -e MYSQL_PASSWORD=$MYSQL_PASSWORD mariadb:latest
else
    docker start $DB_CONTAINER_NAME
fi


docker restart $FPM_CONTAINER_NAME $NGINX_CONTAINER_NAME
