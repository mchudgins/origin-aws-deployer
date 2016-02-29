#! /usr/bin/python

import sys
import yaml

def main(argv):

	yaml_file = argv[0]
	public_ip = argv[1]

	with open( yaml_file ) as f:
		list_doc = yaml.load( f )

	list_doc[ 'assetConfig' ][ 'masterPublicURL' ] = 'https://' + public_ip + ':8443/'
	list_doc[ 'assetConfig' ][ 'publicURL' ] = 'https://' + public_ip + ':8443/console/'

	list_doc[ 'oauthConfig' ][ 'assetPublicURL' ] = 'https://' + public_ip + ':8443/console/'
	list_doc[ 'oauthConfig' ][ 'masterPublicURL' ] = 'https://' + public_ip + ':8443/'

	list_doc[ 'masterPublicURL' ] = 'https://' + public_ip + ':8443'

	list_doc[ 'networkConfig' ][ 'networkPluginName' ] = 'redhat/openshift-ovs-subnet'

	with open( yaml_file, "w" ) as f:
		yaml.dump(list_doc, f)

if __name__ == "__main__":
	main(sys.argv[1:])
