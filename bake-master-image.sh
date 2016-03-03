

#! /bin/bash

# prepare to launch an ec2 instance in AWS

BASE_AMI="ami-1033037a"
KEY_NAME="apache-test"
SSHOPTS="-q -o ConnectTimeout=5 -o CheckHostIP=no -o StrictHostKeychecking=no -i ${HOME}/certs/${KEY_NAME}.pem"
UPTIME_CMD="uptime -s"

WORKDIR=`mktemp -d`
cd ${WORKDIR}

# build the cloud init file the instance will run on boot
BOOT_FILE=boot.sh
cat <<"EOF" > ${BOOT_FILE}
#! /bin/bash

DEFAULT_OPENSHIFT_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.1.3/openshift-origin-server-v1.1.3-cffae05-linux-64bit.tar.gz

TARFILE=ose.tar.gz
PUBLIC_IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4/`
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
AMI_ID=`curl http://169.254.169.254/latest/meta-data/ami-id`
REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`

if [[ -z "${OPENSHIFT_DOWNLOAD}" ]]; then
  OPENSHIFT_DOWNLOAD=${DEFAULT_OPENSHIFT_DOWNLOAD}
fi

# some magic voodoo to parse the download string and pluck out the
# the version number from /vX.X.X/ in the URL
RELEASE=`echo ${OPENSHIFT_DOWNLOAD} | sed 's/^.*\/v//' | sed 's/\/.*//'`

echo "Using ${OPENSHIFT_DOWNLOAD} as the source for Openshift Origin, v${RELEASE}."

# hmmmm, need to set the hostname to something the AWS DNS server knows
hostname `hostname -s`.ec2.internal

# install dependencies of Openshift + tcpdump and nano for troubleshooting
dnf upgrade
dnf install -y bash-completion bind-utils bridge-utils jq \
  iptables-services nano net-tools tcpdump python
pip install --upgrade pip
pip install awscli pyyaml
dnf clean all

sudo systemctl enable rc-local.service

# download & setup the openshift runtimes
mkdir -p /opt/origin
cd /opt/origin
mkdir bin
curl -sL ${OPENSHIFT_DOWNLOAD} -o /tmp/${TARFILE} \
  && tar xvfz /tmp/${TARFILE} --strip-components=1 \
    --directory bin \
  && rm /tmp/${TARFILE}

#-----------------------------------------------------------
# Create initial-setup.sh
#-----------------------------------------------------------

cat <<"EOF_SETUP" >bin/initial-setup.sh
#! /bin/bash

MASTER_IP=192.168.1.10
DEFAULT_MASTER_DNS=dev.dstcorp.io
DEFAULT_CLUSTER_UPLOAD=s3://dstresearch/cluster-configs
REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`

if [[ -e /tmp/launch-config ]]; then
  source /tmp/launch-config
fi

if [[ -z "${MASTER_DNS}" ]]; then
  MASTER_DNS=${DEFAULT_MASTER_DNS}
fi

if [[ -z "${CLUSTER_UPLOAD}" ]]; then
  CLUSTER_UPLOAD=${DEFAULT_CLUSTER_UPLOAD}
fi


# create the master certificates and config

/opt/origin/bin/openshift start master \
  --listen=https://${MASTER_IP}:8443 \
  --master=https://${MASTER_IP}:8443 \
  --public-master=https://${MASTER_DNS}:8443 \
  --network-plugin=redhat/openshift-ovs-multitenant \
  --write-config=openshift.local.config/master

# now that the CA has been created (by the start master cmd),
# we need to create the node config's and certificates
# we'll create twenty of 'em for ip addresses 192.168.1.20 thru .39

for i in `seq 20 39`; do
  NODE=192-168-1-$i;
  NODEIP=192.168.1.$i;
  /opt/origin/bin/oadm create-node-config \
    --node-dir=openshift.local.config/ip-${NODE} \
    --node=ip-${NODE}.ec2.internal \
    --hostnames=ip-${NODE}.ec2.internal,${NODEIP} \
    --network-plugin=redhat/openshift-ovs-multitenant \
    --master=https://${MASTER_IP}:8443;

  # tweak the mtu settings.  AWS supports an mtu of 9000
  sed -i 's/mtu: *1450/mtu: 8950/' openshift.local.config/ip-${NODE}/node-config.yaml
done

# copy the configs up to s3
tar cvfz /tmp/config.tar.gz openshift.local.config \
  && aws s3 --region=${REGION} cp \
    /tmp/config.tar.gz ${CLUSTER_UPLOAD}/${MASTER_DNS}/config.tar.gz \
  && rm /tmp/config.tar.gz

# now setup the local machine's config as a master
mkdir -p /etc/origin/openshift.local.config/master
#mkdir -p /etc/origin/openshift.local.config/`hostname -s`
cp -ra openshift.local.config/master/* /etc/origin/openshift.local.config/master
#cp -ra openshift.local.config/`hostname -s` /etc/origin/openshift.local.config/`hostname -s`
rm -rf openshift.local.config
EOF_SETUP
chmod +x bin/initial-setup.sh

#-----------------------------------------------------------
# Create boot script to launch openshift
#-----------------------------------------------------------

cat <<"EOF_RC_LOCAL" >/etc/rc.d/rc.local
#! /bin/bash

MASTER_IP=192.168.1.10
DEFAULT_MASTER_DNS=dev.dstcorp.io
DEFAULT_CLUSTER_UPLOAD=s3://dstresearch/cluster-configs
REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`

MASTER_CONFIG=/etc/origin/openshift.local.config/master/master-config.yaml
OSO_BIN=/opt/origin/bin

if [[ -e /tmp/launch-config ]]; then
  source /tmp/launch-config
fi

if [[ -z "${MASTER_DNS}" ]]; then
  MASTER_DNS=${DEFAULT_MASTER_DNS}
fi

# create the initial config, if it doesn't exist
if [[ ! -f ${MASTER_CONFIG} ]]; then
  ${OSO_BIN}/initial-setup.sh
fi

# launch openshift
${OSO_BIN}/openshift start master \
  --loglevel 5 \
  --config=${MASTER_CONFIG} \
    >>/var/log/openshift-master.log 2>>/var/log/openshift-master.log &

EOF_RC_LOCAL
chmod +x /etc/rc.d/rc.local

# now, create the image
TODAY=`date +%Y%m%d`
BASE_OS=`cat /etc/redhat-release`
UNAME=`uname -rvmpio`
AMI_DESC=`aws ec2 --region=${REGION} describe-images --image-ids ami-1033037a | jq '.Images[0].Name'`

# copy the /var/log/cloud-init-output.log to s3, so we can track what happened.
echo "/var/log/cloud-init-output.log uploaded to s3://dstresearch/logs/Openshift-v${RELEASE}-Master-${TODAY}-${INSTANCE_ID}.log"
echo "Requesting AWS create image:  Openshift-v${RELEASE}-Master-${TODAY}"
aws s3 cp --region=${REGION} /var/log/cloud-init-output.log \
  s3://dstresearch/logs/Openshift-v${RELEASE}-Master-${TODAY}-${INSTANCE_ID}.log

aws ec2 create-image --instance-id ${INSTANCE_ID} \
  --region=${REGION} \
  --name "Openshift-v${RELEASE}-Master-${TODAY}" \
  --description "Master (only) built from image ${AMI_ID}:${AMI_DESC} (Baker instance ${INSTANCE_ID})"

EOF
chmod +x ${BOOT_FILE}

# launch the instance
echo "Launching AWS instance...."
LAUNCH_DATA=`aws ec2 run-instances --image-id ${BASE_AMI} \
  --count 1 \
  --user-data file://${PWD}/${BOOT_FILE} \
  --key-name ${KEY_NAME} \
  --instance-type m4.large \
  --subnet-id subnet-1d39e437 \
  --iam-instance-profile Name=imageBaker \
  --associate-public-ip-address`

if [[ $? -ne 0 ]]; then
  ERROR=$?
  echo "Unable to launch instance:  ${LAUNCH_DATA}"
  exit ${ERROR}
fi

# get the instance ID
INSTANCE_ID=`echo ${LAUNCH_DATA} | jq '.Instances[0].InstanceId' | sed 's/\"//g'`

echo "Waiting for instance ${INSTANCE_ID} to be assigned a public IPADDR"
PUBLIC_IP=`aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq '.Reservations[0].Instances[0].PublicIpAddress' | sed 's/\"//g'`
echo ${PUBLIC_IP}
while [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" = "null" ]]; do
  sleep 10
  echo -n '.'
  PUBLIC_IP=`aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq '.Reservations[0].Instances[0].PublicIpAddress' | sed 's/\"//g'`
done

# tag it
echo "Tagging ec2 instance"
aws ec2 create-tags --resources ${INSTANCE_ID} \
  --tags Key="Name",Value="master baker" \
    Key="Expires",Value="`date --date "2 hours" +%Y%m%d%H%M`"
while [[ $? -ne 0 ]]; do
  sleep 2
  aws ec2 create-tags --resources ${INSTANCE_ID} \
    --tags Key="Name",Value="master baker" \
      Key="Expires",Value="`date --date "2 hours" +%Y%m%d%H%M`"
done

#
# tricky bit.  We want to kill the instance when the AWS image creation process
# has completed.  Knowing when that happens is hard.  We don't have the new
# ami-id since the instance shutdowns immediately when the create-image request
# is made to AWS.  Furthermore, AWS will shutdown the O.S. in order to create the image.
# This means we have to wait for the image to reboot (or monitor the status
# of the ami_id, which we don't have).  Therefore, we determine if the system
# has re-booted by monitoring the 'uptime -s' value (which gives the time of the
# current boot up).
#

# wait for the instance to complete the boot enuf to have OpenSSH running
# and then get the 'uptime -s' value
INTERVAL=10
echo ""
echo "PUBLIC IP Address of ${INSTANCE_ID} is ${PUBLIC_IP}"
echo "Waiting for instance ${INSTANCE_ID} to complete boot process (${INTERVAL}s intervals)."
UPTIME=`ssh ${SSHOPTS} fedora@${PUBLIC_IP} ${UPTIME_CMD}`
while [[ -z "${OLD_UPTIME}" ]]; do
  sleep ${INTERVAL}
  echo -n '.'
  UPTIME=`ssh ${SSHOPTS} fedora@${PUBLIC_IP} ${UPTIME_CMD}`
  if [[ $? -eq 0 ]]; then
    OLD_UPTIME=${UPTIME}
  fi
done

# now wait for the 'uptime -s' value to change
INTERVAL=60
echo ""
echo "Waiting for instance to complete the AMI creation process (${INTERVAL}s intervals)."
NEW_UPTIME=`ssh ${SSHOPTS} fedora@${PUBLIC_IP} ${UPTIME_CMD}`
while [[ -z "${NEW_UPTIME}" || ${NEW_UPTIME} = ${OLD_UPTIME} ]]; do
  sleep ${INTERVAL}
#  echo -n '.'
  NEW_UPTIME=`ssh ${SSHOPTS} fedora@${PUBLIC_IP} ${UPTIME_CMD}`
  echo "NEW_UPTIME=${NEW_UPTIME}, OLD_UPTIME=${UPTIME}"
done

# looks like it's done.  terminate the instance
echo "Complete!  Terminating instance ${INSTANCE_ID}."
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}

# done
cd -
rm -rf ${WORKDIR}
