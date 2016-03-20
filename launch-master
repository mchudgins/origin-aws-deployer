#! /bin/bash
#
# Launches an Openshift Master instance in AWS.
#
# Example:  launch-master <cluster-name> <instance-type> <key-name>
#

MASTER_DNS=$1
INSTANCE_TYPE=$2
KEY_NAME=$3

echo $1, $2, $3

if [[ -z "${INSTANCES}" ]]; then
echo creating cloudformation
aws cloudformation create-stack --stack-name oso-master \
  --template-body file:///${PWD}/oso-master.json \
  --parameters ParameterKey=InstanceType,ParameterValue=${INSTANCE_TYPE} \
    ParameterKey=KeyName,ParameterValue=${KEY_NAME} \
    ParameterKey=ClusterName,ParameterValue=${MASTER_DNS}

if [[ $? -ne 0 ]]; then
  exit 1
fi

fi

# wait for instance with name=master0 and clusterName=${MASTER_DNS} to show up
# as running

found=0
while [[ ${found} -eq 0 ]]; do
#  sleep 10
#  INSTANCES=`aws ec2 describe-instances`
  maxRes=`echo ${INSTANCES} | jq '.Reservations | length'`
  echo $maxRes reservations

  for i in `seq 1 ${maxRes}`; do
    maxInstances=`echo ${INSTANCES} | jq ".Reservations[$i-1].Instances | length"`
    echo    $maxInstances
    for j in `seq 1 ${maxInstances}`; do
      state=`echo ${INSTANCES} \
              | jq ".Reservations[$i-1].Instances[$j-1].State.Name" \
              | sed 's/"//g'`
      echo        State: $state

      instanceId=`echo ${INSTANCES} \
              | jq ".Reservations[$i-1].Instances[$j-1].InstanceId" \
              | sed 's/"//g'`
      echo examining instance ${instanceId}, $i, $j

      if [[ ${state,,} != "running" ]]; then
        continue
      fi

      maxTags=`echo ${INSTANCES} \
                | jq ".Reservations[$i-1].Instances[$j-1].Tags | length"`
      echo ${maxTags} tags found
      for k in `seq 1 ${maxTags}`; do
        tagName=`echo ${INSTANCES} \
                  | jq ".Reservations[$i-1].Instances[$j-1].Tags[$k-1].Key" \
                  | sed 's/"//g'`
        echo $tagName
        if [[ ${tagName,,} == "cluster" ]]; then
            echo found a cluster tag.
            clusterName=`echo ${INSTANCES} \
                      | jq ".Reservations[$i-1].Instances[$j-1].Tags[$k-1].Value" \
                      | sed 's/"//g'`

            if [[ ${clusterName} == ${MASTER_DNS} ]]; then
              echo "${clusterName} lives"
              found=1
              MASTER=${instanceId}
            fi
        fi
      done
    done
  done

echo ${MASTER} is the one to watch

#
# associate an Elastic IP with the master instance
#

# find an elastic ip that is not in use and has a Name==${MASTER_DNS}


#
# now launch the master-script in the master.
# the master script will prime the cluster.
#

exit
done
