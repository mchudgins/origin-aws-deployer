#! /bin/bash

RELEASE=1.1.3
SERVER_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz
TARFILE=ose.tar.gz

sudo hostname `hostname -s`.ec2.internal

if [[ ! -e .master-installed ]]; then
  sudo dnf install -y bash-completion bind-utils bridge-utils iptables-services nano net-tools openvswitch python
  sudo pip install --upgrade pip
  sudo pip install pyyaml

#sudo systemctl enable openvswitch
#sudo systemctl start openvswitch

  curl -sL ${SERVER_DOWNLOAD} -o ${TARFILE}
  tar xvfz ${TARFILE} --strip-components=1
  #sudo sed -i "s/^OPTIONS.*/OPTIONS=\'--selinux-enabled --insecure-registry 172.30.0.0\/16\'/g" /etc/sysconfig/docker
  #sudo systemctl enable docker
  #sudo systemctl start docker

  gen-oso-config && aws s3 cp oso-config.tar.gz s3://dstresearch/backups/oso/

  touch .master-installed
fi

sudo ./openshift start master \
  --loglevel 5 \
  --config=./openshift.local.config/master/master-config.yaml \
  >>/tmp/master.log 2>>/tmp/master.log &