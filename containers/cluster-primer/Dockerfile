#
# Build file for cluster-primer
#

FROM		debian
MAINTAINER	Mike Hudgins <mchudgins@dstsystems.com> @mchudgins

ENTRYPOINT ["/cluster-primer.sh"]

# update the package repo info
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		python-pip \
	&& pip install --upgrade pip \
	&& pip install awscli pyyaml \
	&& apt-get clean \
	&& rm -r /var/lib/apt/lists/*

COPY cluster-primer /cluster-primer.sh
