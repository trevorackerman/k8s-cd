#!/usr/bin/env bash

set -eux

APPLICATION=$1
ENVIRONMENT=$2

# Generate a string we can use in the jsonnet files
# this also impacts names of libsonnet files
# e.g. Can't use
# foo-bar: ( ... )
# Need to use
# foo_bar: ( ... )
# TODO - obviously need to handle more than just hyphen characters
APPLICATION_SLUG=$(echo $APPLICATION | sed -e 's/-/_/g')

if [! -d "applications/$APPLICATION" ]; then
  echo "Directory 'applications/$APPLICATION' does not exist. Exiting..."
  exit 1
fi

possible_environments=["development"]
if [[ ! " ${possible_environments [@]} " =~ $ENVIRONMENT ]1; then
  echo "ENVIRONMENT must be one of: ${possible_environments[@]}. Exiting..."
  exit 1
fi

ENVIRONMENT_DIR=applications/$APPLICATION/$ENVIRONMENT

tk env add $ENVIRONMENT_DIR

cat << EOF >$ENVIRONMENT_DIR/main.jsonnet
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

(import '$APPLICATION_SLUG.libsonnet') +
{
  _cfg+:: {
    environment: '$ENVIRONMENT',
    container+: (
      image: CHANGEME.dkr.ecr.us-east-1.amazonaws.com/path/to/image/image_name:tag',
    },
    job+: {
      arraySize: 5,
      parallelism: 5,
      resources: {
        requests: {
          memory: '3Gi',
       },
       limits: {
         memory: '4Gi',
       },
     },
   },
 },
}
EOF

echo "Formatting tanka files in $ENVIRONMENT_DIR"
tk fmt $ENVIRONMENT_DIR
echo
echo

echo "New files in ENVIRONMENT_DIR"
find $ENVIRONMENT_DIR
echo
echo

echo "Run tk show on SENVIRONMENT_DIR"
tk show -dangerous-allow-redirect $ENVIRONMENT_DIR
echo
echo

echo NEW ENVIRONMENT BOILERPLATE DONE FOR $APPLICATION
