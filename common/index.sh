#!/bin/sh
set -e

TERM=xterm
DEBIAN_FRONTEND=noninteractive

root=$(dirname $(dirname $(realpath -s $0)))
name=${name:-liveblog}
repo=/opt/$name
repo_remote=${repo_remote:-'https://github.com/liveblog/liveblog.git'}
repo_branch=${repo_branch:-}
env=$repo/env
envfile=$repo/envfile
action=${action:-do_install}

_envfile_end() {
    cat <<EOF

S3_THEMES_PREFIX=
AMAZON_S3_SUBFOLDER=
EOF
}

_envfile() {
    . $root/common/envfile.tpl > $envfile
    echo "$(_envfile_end)" >> $envfile
}

_repo() {
    [ -d $repo ] || git clone --depth=1 $repo_remote $repo
    if [ -n "$repo_branch" ]; then
        cd $repo
        git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        git fetch origin $repo_branch
        git checkout $repo_branch
    fi
}

_venv() {
    path=$1
    python3 -m venv $path
    echo "export \$(cat $envfile)" >> $path/bin/activate
    . $path/bin/activate
    pip install -U pip wheel
}

_supervisor_adds() { :; }
_supervisor() {
    supervisor_tpl=${supervisor_tpl:-"$root/common/supervisor.tpl"}
    supervisor_adds="$(_supervisor_adds)"

    . $supervisor_tpl > /etc/supervisor/conf.d/${name}.conf
    systemctl enable supervisor
    systemctl restart supervisor
}

_npm() {
    # node & npm
    curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
    apt-get install -y nodejs
    [ -f /usr/bin/node ] || ln -s /usr/bin/nodejs /usr/bin/node
}

_nginx_locations() { :; }
_nginx() {
    nginx_tpl=${nginx_tpl:-"$root/common/nginx.tpl"}
    nginx_locations="$(_nginx_locations)"

    wget -qO - http://nginx.org/keys/nginx_signing.key | sudo apt-key add -
    echo "deb http://nginx.org/packages/ubuntu/ xenial nginx" \
        > /etc/apt/sources.list.d/nginx.list

    apt-get -y update
    apt-get -y install nginx

    path=/etc/nginx/conf.d
    cp $root/common/nginx_params.conf $path/params.conf
    . $nginx_tpl > $path/default.conf

    systemctl enable nginx
    systemctl restart nginx
}

do_init() {
    apt-get -y install --no-install-recommends \
    git python3 python3-dev python3-venv supervisor \
    build-essential libffi-dev \
    libtiff5-dev libjpeg8-dev zlib1g-dev \
    libfreetype6-dev liblcms2-dev libwebp-dev \
    curl libfontconfig libssl-dev

    locale-gen en_US.UTF-8

    _repo
    _envfile
}

do_backend() {
    _venv $env
    pip install -U -r $repo/server/requirements.txt

    _supervisor
}

do_frontend() {
    _npm
    npm install -g grunt-cli bower

    cd $repo/client
    npm install
    bower --allow-root install
    grunt build --server='http://localhost:5000/api' --ws='ws://localhost:5100' --force
}

do_prepopulate() {
    . $env/bin/activate
    cd $repo/server
    python manage.py app:initialize_data
    python manage.py users:create -u admin -p admin -e 'admin@example.com' --admin true
    python manage.py register_local_themes
}

do_finish() {
    _nginx
}

do_services() {
    apt-get -y install wget software-properties-common

    #elasticsearch
    wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    echo "deb http://packages.elastic.co/elasticsearch/1.7/debian stable main" \
        > /etc/apt/sources.list.d/elastic.list

    #mongodb
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927
    echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-3.2.list

    #redis
    add-apt-repository -y ppa:chris-lea/redis-server

    #install
    apt-get -y update
    apt-get -y install \
        openjdk-8-jre-headless \
        elasticsearch \
        mongodb-org-server \
        redis-server

    systemctl enable elasticsearch mongod redis-server
    systemctl restart elasticsearch mongod redis-server
}

do_install() {
    apt-get -y autoremove --purge ntpdate
    apt-get -y update

    [ ! -d $repo/client/dist ] || [ -n "$force_frontend" ] && frontend=1

    do_init
    [ -n "$services" ] && do_services
    do_backend
    [ -n "$frontend" ] && do_frontend
    [ -n "$prepopulate" ] && do_prepopulate
    do_finish

    apt-get -y clean
}
