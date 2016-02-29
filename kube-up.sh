#! /bin/bash

RELEASE=1.1.3
SERVER_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz
TARFILE=ose.tar.gz
PUBLIC_IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4/`
TWEAK_MASTER=./mod-config.py
MASTER_CONFIG=${PWD}/openshift.local.config/master/master-config.yaml

sudo hostname `hostname -s`.ec2.internal

sudo dnf install -y bash-completion bind-utils bridge-utils iptables-services nano net-tools openvswitch python
sudo pip install --upgrade pip
sudo pip install pyyaml

#sudo systemctl enable openvswitch
#sudo systemctl start openvswitch

curl -sL ${SERVER_DOWNLOAD} -o /tmp/${TARFILE}
tar xvfz /tmp/${TARFILE} --strip-components=1

  #sudo sed -i "s/^OPTIONS.*/OPTIONS=\'--selinux-enabled --insecure-registry 172.30.0.0\/16\'/g" /etc/sysconfig/docker
  #sudo systemctl enable docker
  #sudo systemctl start docker

./gen-oso-config \
  && echo "tweaking master config file " ${MASTER_CONFIG} " with " ${PUBLIC_IP} \
  && ${TWEAK_MASTER} ${MASTER_CONFIG} ${PUBLIC_IP} \
  && tar cvfz /tmp/oso-config.tar.gz openshift.local.config \
  && aws s3 cp /tmp/oso-config.tar.gz s3://dstresearch/backups/oso/ \
  && rm /tmp/oso-config.tar.gz

sudo ./openshift start master \
  --loglevel 5 \
  --config=${MASTER_CONFIG} \
  >>/tmp/master.log 2>>/tmp/master.log &
