

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
dnf install -y bash-completion bind-utils bridge-utils docker ethtool jq \
  iptables-services nano net-tools openvswitch python tcpdump
pip install --upgrade pip
pip install awscli pyyaml
dnf clean all

# enable the services the image will need on launch
sudo systemctl enable rc-local.service
sudo systemctl enable openvswitch
sudo systemctl enable docker

# download & setup the openshift runtimes
mkdir -p /opt/origin
cd /opt/origin
mkdir bin
curl -sL ${OPENSHIFT_DOWNLOAD} -o /tmp/${TARFILE} \
  && tar xvfz /tmp/${TARFILE} --strip-components=1 \
    --directory bin \
  && rm /tmp/${TARFILE}

# download and setup the openshift sdn scripts
aws s3 cp --region=${REGION} s3://dstresearch/backups/oso/node-sdn-scripts.tar.gz \
    /tmp/node-sdn-scripts.tar.gz \
  && tar xvfz /tmp/node-sdn-scripts.tar.gz --directory /sbin

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

# debug:  print current VARS for initial-setup.sh
echo "current VARS for initial-setup.sh"
echo "MASTER_DNS:  ${MASTER_DNS}"
echo "CLUSTER_UPLOAD:  ${CLUSTER_UPLOAD}"
echo "REGION:  ${REGION}"
echo "curling:  `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`"

# see if there's a suitably named config.tar.gz on s3
aws s3 --region=${REGION} cp ${CLUSTER_UPLOAD}/${MASTER_DNS}/config.tar.gz /tmp \
  && mkdir -p /etc/origin/openshift.local.config \
  && tar xvfz /tmp/config.tar.gz --directory /etc/origin \
  && rm /tmp/config.tar.gz \
  && echo "downloaded config.tar.gz from s3" \
  && exit 0

# setup the aws.conf file, per https://docs.openshift.org/latest/install_config/configuring_aws.html
AWSCONFSUBDIR=/etc/aws
AWSCONF=${AWSCONFSUBDIR}/aws.conf
if [[ ! -f ${AWSCONF} ]]; then
  mkdir -p ${AWSCONFSUBDIR}
  echo "[Global]" >${AWSCONF}
  echo "Zone = ${REGION}" >>${AWSCONF}
fi

EOF_SETUP
chmod +x bin/initial-setup.sh

#-----------------------------------------------------------
# Create boot script to launch openshift
#-----------------------------------------------------------

cat <<"EOF_RC_LOCAL" >bin/launch-node.sh
#! /bin/bash

DEFAULT_MASTER_IP=192.168.1.10
DEFAULT_CLUSTER_UPLOAD=s3://dstresearch/cluster-configs
REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`
NODE=`hostname -s`
NODE_CONFIG=/etc/origin/openshift.local.config/${NODE}/node-config.yaml
OSO_BIN=/opt/origin/bin

# hmmmm, need to set the hostname to something the AWS DNS server knows
hostname `hostname -s`.ec2.internal

if [[ -e /tmp/launch-config ]]; then
  source /tmp/launch-config
fi

if [[ -z "${MASTER_IP}" ]]; then
  MASTER_IP=${DEFAULT_MASTER_IP}
fi

# debug:  print current VARS for launch-master.sh
echo "current VARS for launch-node.sh"
echo "MASTER_IP:  ${MASTER_IP}"
echo "REGION:  ${REGION}"
echo "NODE_CONFIG:  ${NODE_CONFIG}"
echo "curling:  `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`"

# create the initial config, if it doesn't exist
if [[ ! -f ${NODE_CONFIG} ]]; then
  ${OSO_BIN}/initial-setup.sh
fi

# launch openshift
${OSO_BIN}/openshift start node \
  --loglevel 5 \
  --config=${NODE_CONFIG} \
    >>/var/log/openshift-node.log 2>>/var/log/openshift-node.log &

EOF_RC_LOCAL
chmod +x bin/launch-node.sh

# now, create the image
TODAY=`date +%Y%m%d%H%M`
BASE_OS=`cat /etc/redhat-release`
UNAME=`uname -rvmpio`
AMI_DESC=`aws ec2 --region=${REGION} describe-images --image-ids ami-1033037a | jq '.Images[0].Name'`

# copy the /var/log/cloud-init-output.log to s3, so we can track what happened.
echo "/var/log/cloud-init-output.log uploaded to s3://dstresearch/logs/Openshift-v${RELEASE}-Node-${TODAY}-${INSTANCE_ID}.log"
echo "Requesting AWS create image:  Openshift-v${RELEASE}-Node-${TODAY}"
cp /var/log/cloud-init-output.log /tmp \
  && gzip /tmp/cloud-init-output.log \
  && aws s3 cp --region=${REGION} /tmp/cloud-init-output.log.gz \
    s3://dstresearch/logs/Openshift-v${RELEASE}-Node-${TODAY}-${INSTANCE_ID}.log.gz

aws ec2 create-image --instance-id ${INSTANCE_ID} \
  --region=${REGION} \
  --name "Openshift-v${RELEASE}-Node-${TODAY}" \
  --description "Node built from image ${AMI_ID}:${AMI_DESC} (Baker instance ${INSTANCE_ID})"

EOF
chmod +x ${BOOT_FILE}

# launch the instance
echo "Launching AWS instance...."
LAUNCH_DATA=`aws ec2 run-instances --image-id ${BASE_AMI} \
  --count 1 \
  --user-data file://${PWD}/${BOOT_FILE} \
  --key-name ${KEY_NAME} \
  --instance-type m3.medium \
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
while [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" = "null" ]]; do
  sleep 10
  echo -n '.'
  PUBLIC_IP=`aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq '.Reservations[0].Instances[0].PublicIpAddress' | sed 's/\"//g'`
done

# tag it
echo "Tagging ec2 instance"
aws ec2 create-tags --resources ${INSTANCE_ID} \
  --tags Key="Name",Value="node baker" \
    Key="Expires",Value="`date --date "2 hours" +%Y%m%d%H%M`"
while [[ $? -ne 0 ]]; do
  sleep 2
  aws ec2 create-tags --resources ${INSTANCE_ID} \
    --tags Key="Name",Value="node baker" \
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
INTERVAL=30
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