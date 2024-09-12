#!/usr/bin/env bash

APPLICATION=$1
ENVIRONMENT=$2
OCI_REPO=${3:-$APPLICATION}
SHORT_SHA=$(git rev-parse --short HEAD)
MANIFEST_DIR="./manifests-$APPLICATION-$ENVIRONMENT-$SHORT_SHA"
MANIFEST_FILE="$MANIFEST_DIR/$APPLICATION-$ENVIRONMENT-$SHORT_SHA.yaml"
OCI_HOST=oci://CHANGEME.dkr.ecr.us-east-1.amazonaws.com
OCI_ENDPOINT="$OCI_HOST/$OCI_REPO"

GIT_SOURCE=$(git config —get remote.origin.url)
GIT_REVISION="$(git branch -show-current)@shal:$(git rev-parse HEAD)"
cksum SMANIFEST_FILE

ls -1 $MANIFEST_FILE
echo "Contents of Manifest File"
cat $MANIFEST_FILE
echo
echo

echo "Going to push artifact with flux"
# Print the command to stdout
cat << EOF
cat $MANIFEST_FILE | \
/usr/local/bin/flux push artifact \
  $OCI_ENDPOINT:$SHORT_SHA \
  -f - \
  --debug \
  --source="$GIT_SOURCE" \
  --revision="$GIT_REVISION" \
  --provider aws
EOF

cat MANIFEST_FILE | \
/usr/local/bin/flux push artifact \
  $OCI_ENDPOINT: $SHORT_SHA \
  -f - \
  --debug \
  --source="$GIT_SOURCE" \
  -—revision="$GIT_REVISION" \
  --provider aws

/usr/local/bin/flux tag artifact \
  $OCI_ENDPOINT:$SHORT_SHA \
  --tag $ENVIRONMENT \
  --provider


