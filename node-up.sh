#! /bin/bash

RELEASE=1.1.3
SERVER_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz
CONFIG_TARBALL=s3://dstresearch/backups/oso/oso-config.tar.gz
TARFILE=ose.tar.gz
NODE=`hostname -s`

if [[ ! -e .oso-installed ]]; then
  dnf install -y bash-completion bind-utils bridge-utils docker ethtool iptables-services nano net-tools openvswitch python
  pip install --upgrade pip
  pip install pyyaml awscli

  hostname ${NODE}.ec2.internal
  sysctl -w net.ipv4.ip_forward=1

  if [[ ! -f /tmp/${TARFILE} ]]; then
        curl -sL ${SERVER_DOWNLOAD} -o /tmp/${TARFILE}
        tar xvfz /tmp/${TARFILE} --strip-components=1
        rm /tmp/${TARFILE}
  fi

  systemctl enable openvswitch
  systemctl start --no-block openvswitch

  systemctl enable docker
  # grrrr, need to start blocker in the delayed-launcher
  #sudo systemctl start --no-block docker
  sed -i "s/^OPTIONS.*/OPTIONS=\'--selinux-enabled --insecure-registry 172.30.0.0\/16\'/g" /etc/sysconfig/docker

  OSO_CONFIG=/tmp/oso-config.tar.gz
  if [[ ! -d openshift.local.config ]]; then
        aws s3 cp ${CONFIG_TARBALL} ${OSO_CONFIG}
        tar xvfz ${OSO_CONFIG} openshift.local.config/${NODE}/
        rm ${OSO_CONFIG}
  fi

  cp openshift-sdn-ovs /sbin/openshift-sdn-ovs
  cp openshift-sdn-docker-setup.sh /sbin

  touch .oso-installed
fi

./delayed-launcher /opt/origin/openshift.local.config/${NODE}/node-config.yaml 60 &
