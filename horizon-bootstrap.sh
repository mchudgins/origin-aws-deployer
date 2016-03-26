#! /bin/bash
KUBECONFIG=/etc/origin/master/admin.kubeconfig
OADM="/opt/origin/bin/oadm --config=$KUBECONFIG"
OC="/opt/origin/bin/oc --config=$KUBECONFIG"

#
# create a project for horizon
#

${OC} new-project horizon \
	--description='follows master branch of git repository' \
	--display-name='Project Horizon (master)'
${OC}	project horizon
${OC} policy add-role-to-group system:image-puller system:serviceaccounts \
  --namespace=horizon
${OC} policy add-role-to-group view system:serviceaccounts \
    --namespace=horizon
${OC} policy add-role-to-user admin mchudgins@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin nlayyadevara@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin bpadmanabhan@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin jskirchmeier@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin cerippenkroeger@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin cmswearingen@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin hmehta@dstsystems.com --namespace=horizon
${OC} policy add-role-to-user admin test@dstresearch.com --namespace=horizon
