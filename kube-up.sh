#! /bin/bash

RELEASE=1.1.3
SERVER_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz
TARFILE=ose.tar.gz
PUBLIC_IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4/`
TWEAK_MASTER=~/mod-config.py

sudo dnf install -y bash-completion bind-utils bridge-utils iptables-services nano net-tools openvswitch python
sudo pip install --upgrade pip
sudo pip install pyyaml 

sudo systemctl enable openvswitch
sudo systemctl start openvswitch

TMPDIR=`mktemp -d`
cd $TMPDIR
curl -sL ${SERVER_DOWNLOAD} -o ${TARFILE}
tar xvfz ${TARFILE} --strip-components=1
sudo sed -i "s/^OPTIONS.*/OPTIONS=\'--selinux-enabled --insecure-registry 172.30.0.0\/16\'/g" /etc/sysconfig/docker
sudo systemctl enable docker
sudo systemctl start docker
sudo ./openshift start --write-config=openshift.local.config
sudo ${TWEAK_MASTER} ${PUBLIC_IP}

sudo ./openshift start master --config=./openshift.local.config/master/master-config.yaml
