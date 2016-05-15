#
# Makefile for testing Openshift Origin on AWS

all: node-up.tar.gz container

node-sdn-scripts.tar.gz: openshift-sdn-ovs openshift-sdn-docker-setup.sh
	tar cvfz $@ $^

deploy: oso-master.json oso-minion.json node-sdn-scripts.tar.gz
	aws s3 cp node-sdn-scripts.tar.gz s3://dstresearch/backups/oso/ \
		&& aws cloudformation validate-template \
			--template-body file:///${PWD}/oso-master.json \
		&& aws s3 cp oso-master.json \
			s3://dstresearch-public/CloudFormation/oso-master.json \
		&& aws cloudformation validate-template \
			--template-body file:///${PWD}/oso-minion.json \
		&& aws s3 cp oso-master.json \
			s3://dstresearch-public/CloudFormation/oso-minion.json

bake-master:
	./bake-master-image.sh

launch-master:
	aws cloudformation create-stack --stack-name oso-master \
	 	--template-body file:///${PWD}/oso-master.json \
		--parameters ParameterKey=InstanceType,ParameterValue=m4.large \
			ParameterKey=KeyName,ParameterValue=apache-test \
			ParameterKey=ClusterName,ParameterValue=dev.dstcorp.io

launch-node0:
	aws cloudformation create-stack --stack-name oso-node0 \
	 	--template-body file:///${PWD}/oso-minion.json \
		--parameters ParameterKey=IPAddress,ParameterValue=192.168.1.20 \
			ParameterKey=NodeName,ParameterValue=node0 \
			ParameterKey=InstanceType,ParameterValue=m4.large

launch-node1:
	aws cloudformation create-stack --stack-name oso-node1 \
	 	--template-body file:///${PWD}/oso-minion.json \
		--parameters ParameterKey=IPAddress,ParameterValue=192.168.1.21 \
			ParameterKey=NodeName,ParameterValue=node1 \
			ParameterKey=InstanceType,ParameterValue=m4.large

launch-node2:
	aws cloudformation create-stack --stack-name oso-node2 \
	 	--template-body file:///${PWD}/oso-minion.json \
		--parameters ParameterKey=IPAddress,ParameterValue=192.168.1.22 \
			ParameterKey=NodeName,ParameterValue=node2 \
			ParameterKey=InstanceType,ParameterValue=m4.large

launch-node3:
	aws cloudformation create-stack --stack-name oso-node3 \
	 	--template-body file:///${PWD}/oso-minion.json \
		--parameters ParameterKey=IPAddress,ParameterValue=192.168.1.23 \
			ParameterKey=NodeName,ParameterValue=node3 \
			ParameterKey=InstanceType,ParameterValue=m4.xlarge

container:
	sudo docker build -t registry.dstresearch.com/cluster-primer containers/cluster-primer
	sudo docker push registry.dstresearch.com/cluster-primer
