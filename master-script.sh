#! /bin/bash
alias oc='sudo /opt/origin/bin/oc --config=/etc/origin/master/admin.kubeconfig'

cat <<__EOF__ >registry-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: dstresearchkey
data:
  .dockercfg: ewoJInJlZ2lzdHJ5LmRzdHJlc2VhcmNoLmNvbSI6IHsKCQkiYXV0aCI6ICJaRzlqYTJWeU9sSmxjMlZoY21Ob1h6RT0iLAoJCSJlbWFpbCI6ICJhZ2VudEBkc3RyZXNlYXJjaC5jb20iCgl9Cn0K
type: kubernetes.io/dockercfg
__EOF__

cat <<__EOF__ >cluster-primer.yaml
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
          value: https://s3.amazonaws.com/dstresearch/cluster-configs/v1.1.3-570/openshift-origin-server-v1.1.3-570-g8f31847-8f31847-linux-64bit.tar.gz
      restartPolicy: Never
      imagePullSecrets:
      - name: dstresearchkey
__EOF__
