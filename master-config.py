#! /usr/bin/python

import sys
import yaml

def main(argv):

	file = argv[ 0 ]
	domainName = argv[ 1 ]
	metricsName= argv[ 2 ]

	with open( file ) as f:
		cfg = yaml.load( f )

	cfg[ 'assetConfig' ][ 'metricsPublicURL' ] = 'https://' + metricsName

#	cfg[ 'assetConfig' ][ 'masterPublicURL' ] = 'https://' + public_ip + ':8443/'
#	cfg[ 'assetConfig' ][ 'publicURL' ] = 'https://' + public_ip + ':8443/console/'

#	cfg[ 'oauthConfig' ][ 'assetPublicURL' ] = 'https://' + public_ip + ':8443/console/'
#	cfg[ 'oauthConfig' ][ 'masterPublicURL' ] = 'https://' + public_ip + ':8443/'

#	cfg[ 'masterPublicURL' ] = 'https://' + public_ip + ':8443'


	cfg[ 'kubernetesMasterConfig' ][ 'apiServerArguments' ] = { 'cloud-config' : [ "/etc/aws/aws.conf" ], 'cloud-provider' : [ "aws" ] }
	cfg[ 'kubernetesMasterConfig' ][ 'controllerArguments' ] = { 'cloud-config' : [ "/etc/aws/aws.conf" ], 'cloud-provider' : [ "aws" ] }

	cfg[ 'routingConfig' ][ 'subdomain' ] = domainName

	identityProvider = {}
	identityProvider[ 'name' ] = "htPassword"
	identityProvider[ 'challenge' ] = "true"
	identityProvider[ 'login' ] = "true"
	identityProvider[ 'mappingMethod' ] = "claim"
	identityProvider[ 'provider' ] = { 'apiVersion' : "v1",  'kind' : "HTPasswdPasswordIdentityProvider", 'file' : "/etc/origin/htpasswd" }
	cfg[ 'oauthConfig' ][ 'identityProviders' ] = [ identityProvider ]

	with open( file, "w" ) as f:
		yaml.dump(cfg, f, default_flow_style=False )

if __name__ == "__main__":
	main(sys.argv[1:])
