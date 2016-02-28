#! /bin/bash

RELEASE=1.1.3
SERVER_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz
CONFIG_TARBALL=s3://dstresearch/backups/oso/oso-config.tar.gz
TARFILE=ose.tar.gz
NODE=`hostname -s`

if [[ ! -e .oso-installed ]]; then
  sudo dnf install -y bash-completion bind-utils bridge-utils docker ethtool iptables-services nano net-tools openvswitch python
  sudo pip install --upgrade pip
  sudo pip install pyyaml awscli

  sudo hostname ${NODE}.ec2.internal
  sudo sysctl -w net.ipv4.ip_forward=1

  if [[ ! -f /tmp/${TARFILE} ]]; then
        curl -sL ${SERVER_DOWNLOAD} -o /tmp/${TARFILE}
        tar xvfz /tmp/${TARFILE} --strip-components=1
  fi

  sudo systemctl enable openvswitch
  sudo systemctl start openvswitch

  sudo sed -i "s/^OPTIONS.*/OPTIONS=\'--selinux-enabled --insecure-registry 172.30.0.0\/16\'/g" /etc/sysconfig/docker
  sudo systemctl enable docker
  sudo systemctl start docker

  if [[ ! -d openshift.local.config ]]; then
        aws s3 cp ${CONFIG_TARBALL} /tmp/oso-config.tar.gz
        tar xvfz /tmp/oso-config.tar.gz
  fi

  sudo cp /home/fedora/openshift-sdn-ovs /sbin/openshift-sdn-ovs
  sudo cp /home/fedora/openshift-sdn-docker-setup.sh /sbin

  touch .oso-installed
fi

sudo ./openshift start node --config=/home/fedora/openshift.local.config/${NODE}/node-config.yaml --loglevel=5
