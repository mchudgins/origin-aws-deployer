#! /bin/bash
#
# run this script on the master.  At least one node must be up when
# this script is run.
#

alias oc='sudo /opt/origin/bin/oc --config=/etc/origin/master/admin.kubeconfig'
OC='sudo /opt/origin/bin/oc --config=/etc/origin/master/admin.kubeconfig'
#aws s3 ls s3://dstresearch/cluster-configs/dev.dstcorp.io/ | awk '{ if ( $4 == "htpasswd" ) { print $1 " " $2 } }'

certsSecrets=`${OC} get secrets | grep -i star.dstcorp.io-certs`
if [[ -z "${certsSecrets}" ]]; then
  echo "You must deploy the secret for the web server BEFORE running this script."
  exit 1
fi

# TODO add these lines to crontab
#@hourly /opt/origin/bin/oadm --config=/etc/origin/master/admin.kubeconfig prune builds --confirm --keep-complete=2 --keep-failed=2 >/dev/null
#@hourly /opt/origin/bin/oadm --config=/etc/origin/master/admin.kubeconfig prune deployments --confirm --keep-complete=2 --keep-failed=2 >/dev/null

(
cat <<__EOF__
apiVersion: v1
kind: Secret
metadata:
  name: dstresearchkey
data:
  .dockercfg: ewoJInJlZ2lzdHJ5LmRzdHJlc2VhcmNoLmNvbSI6IHsKCQkiYXV0aCI6ICJaRzlqYTJWeU9sSmxjMlZoY21Ob1h6RT0iLAoJCSJlbWFpbCI6ICJhZ2VudEBkc3RyZXNlYXJjaC5jb20iCgl9Cn0K
type: kubernetes.io/dockercfg
__EOF__
) | ${OC} create -f -

(
cat <<__EOF__
apiVersion: extensions/v1beta1
kind: Job
metadata:
  name: cluster-primer
spec:
  selector:
    matchLabels:
      app: cluster-primer
  template:
    metadata:
      name: cluster-primer
      labels:
        app: cluster-primer
    spec:
      containers:
      - name: cluster-primer
        image: registry.dstresearch.com/cluster-primer:latest
        env:
        - name: CLUSTER
          value: dev.dstcorp.io
        - name: OPENSHIFT_DOWNLOAD
          value: https://github.com/openshift/origin/releases/download/v1.2.0-rc2/openshift-origin-server-v1.2.0-rc2-642f0af-linux-64bit.tar.gz
      restartPolicy: Never
      imagePullSecrets:
      - name: dstresearchkey
__EOF__
) | ${OC} create -f -
