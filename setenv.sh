#! /bin/bash
#
# Set the version of Openshift and the base AWS AMI here.
# this file gets 'included' by the various baking/launching scripts
export OPENSHIFT_DOWNLOAD=https://github.com/openshift/origin/releases/download/v1.2.1/openshift-origin-server-v1.2.1-5e723f6-linux-64bit.tar.gz
export BASE_AMI=ami-11bd2406
