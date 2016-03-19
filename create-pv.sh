#! /bin/bash
#
# this script monitors AWS Volumes and creates Persistent Volumes
# for each Volume in AWS that has a 'cluster' tag == $MASTER_DNS
# AND .State == 'Available'
#

OC="/opt/origin/bin/oc --config=/etc/origin/master/admin.kubeconfig"
INTERVAL=60
DEFAULT_MASTER_DNS="dev.dstcorp.io"
#REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`

if [[ -z "${REGION}" ]]; then
  REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[abcdefg]$//'`
fi

if [[ -z "${MASTER_DNS}" ]]; then
  MASTER_DNS=${DEFAULT_MASTER_DNS}
fi

if [[ -z "${VOLUMES}" ]]; then
  VOLUMES=`aws ec2 --region=${REGION} describe-volumes --filter Name=status,Values=available`
fi

# PV has the list of persistent volumes defined for the cluster
if [[ -z "${PV}" ]]; then
  PV=`${OC} get pv -o json`
fi

# translate the PV (json) into a string of volumeID's
max=`echo ${PV} | jq '.items | length'`
for i in `seq 1 $max`; do
  NEWPV=`echo $PV | jq ".items[$i-1].spec.awsElasticBlockStore.volumeID" | sed 's/"//g'`
  PVLIST="${PVLIST} ${NEWPV}"
done
if [[ -z "${PVLIST}" ]]; then
  echo "No existing volume claims found defined within the cluster ${MASTER_DNS}"
else
  echo "Existing volume claims found for ${PVLIST}"
fi

# VOLUMES has the list of available volumes
max=`echo ${VOLUMES} | jq '.Volumes | length'`
for i in `seq 1 $max`; do
  # if the volume is already known to the cluster, then skip it
  volId=`echo ${VOLUMES} | jq .Volumes[$i-1].VolumeId | sed 's/"//g'`
  found=0
  for j in ${PVLIST}; do
    if [[ ${volId} == ${j} ]]; then
      echo found ${volId} in ${PVLIST}
      found=1
    fi
  done

  if [[ ${found} -eq 1 ]]; then
    echo skipping ${volId}
    continue
  fi

  # see how many tags exist
  tags=`echo ${VOLUMES} | jq ".Volumes[$i-1].Tags | length"`
  # iterate the tags looking for 'cluster' == $MASTER_DNS
  for j in `seq 1 $tags`; do
    key=`echo ${VOLUMES} | jq .Volumes[$i-1].Tags[$j-1].Key | sed 's/"//g'`
    if [[ ${key,,} == 'cluster' ]]; then
      value=`echo ${VOLUMES} | jq .Volumes[$i-1].Tags[$j-1].Value | sed 's/"//g'`
      if [[ ${value,,} == "${MASTER_DNS}" ]]; then
        size=`echo ${VOLUMES} | jq .Volumes[$i-1].Size`
        echo "Creating volume claim for ${volId}"
        (
        cat <<_EOF_
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $volId
spec:
  capacity:
    storage: ${size}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  awsElasticBlockStore:
    fsType: ext4
    volumeID: $volId
_EOF_
      ) | ${OC} create -f -
      fi
    fi
  done
done

