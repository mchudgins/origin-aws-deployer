#! /usr/bin/python

import sys
import yaml

def main(argv):

	config = argv[0]

	with open( config ) as f:
		list_doc = yaml.load( f )

	list_doc[ 'networkConfig' ][ 'mtu' ] = 8950
	list_doc[ 'networkConfig' ][ 'networkPluginName' ] = "redhat/openshift-ovs-multitenant"

	with open( config, "w" ) as f:
		yaml.dump(list_doc, f)

if __name__ == "__main__":
	main(sys.argv[1:])
