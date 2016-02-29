#
# Makefile for testing Openshift Origin on AWS

all: kube-up.tar.gz node-up.tar.gz

kube-up.tar.gz: kube-up.sh mod-config.py gen-oso-config
	tar cvfz $@ $^

node-up.tar.gz: node-up.sh mod-node-config.py openshift-sdn-ovs openshift-sdn-docker-setup.sh
	tar cvfz $@ $^

deploy: kube-up.tar.gz node-up.tar.gz
	aws s3 cp kube-up.tar.gz s3://dstresearch/backups/oso/
	aws s3 cp node-up.tar.gz s3://dstresearch/backups/oso/
