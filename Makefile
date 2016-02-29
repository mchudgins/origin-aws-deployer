#
# Makefile for testing Openshift Origin on AWS

all: kube-up.tar.gz node-up.tar.gz

kube-up.tar.gz: kube-up.sh mod-config.py mod-node-config.py gen-oso-config
	tar cvfz $@ $^

node-up.tar.gz: node-up.sh openshift-sdn-ovs openshift-sdn-docker-setup.sh
	tar cvfz $@ $^

deploy: kube-up.tar.gz node-up.tar.gz
	aws s3 cp kube-up.tar.gz s3://dstresearch/backups/oso/
	aws s3 cp node-up.tar.gz s3://dstresearch/backups/oso/
	aws cloudformation validate-template \
		--template-body file:///${PWD}/oso-master.json \
		&& aws s3 cp oso-master.json \
			s3://dstresearch-public/CloudFormation/oso-master.json

create-stack:
	aws cloudformation create-stack --stack-name oso-master \
	 	--template-body file:///${PWD}/oso-master.json \
		--parameters ParameterKey=InstanceType,ParameterValue=t2.micro,ParameterKey=KeyName,ParameterValue=apache-test
