#!/usr/bin/env bash

APPLICATION=$1
ENVIRONMENT=$2
APP_GROUP=$3
OCI_REPO=${4:-$APPLICATION}
echo "Getting short sha"
SHORT_SHA=$(git rev-parse -short HEAD)
MANIFEST_DIR="/manifests-$APPLICATION-$ENVIRONMENT-$SHORT_SHA"
MANIFEST_FILE="SMANIFEST_DIR/$APPLICATION-$ENVIRONMENT-$SHORT_SHA.yaml"
OCI_HOST=oci://CHANGEME.dkr.ecr.us-east-1.amazonaws.com
OCI_ENDPOINT="$OCI_HOST/$OCI_REPO"
JSONNET_DIR=./applications/$APPLICATION/$ENVIRONMENT
CLUSTER="$(ENVIRONMENT)-$(APP_GROUP}"

if [ ! -d "$JSONNET_DIR" ]; then
  echo "Skipping $APPLICATION $ENVIRONMENT, no application directory found"
  echo "publish_manifest=false" » "$GITHUB_OUTPUT"
  exit 0
fi

if [ ! -f "$JSONNET_DIR/main.jsonnet" ]; then
  echo "Skipping $APPLICATION $ENVIRONMENT, main.jsonnet missing from application directory"
  echo "publish_manifest=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

__DIR=$(pwd)
cd applications/$APPLICATION
echo "jsonnet-bundler updating applications/$APPLICATION"
jb update
cd $__DIR
echo "jsonnet-bundler updated applications/$APPLICATION"
mkdir -p $MANIFEST_DIR
git log --pretty=format:"# %h, %aI, %an, %s%n" -1 > $MANIFEST_FILE
tk show $JSONNET_DIR --dangerous-allow-redirect >> $MANIFEST_FILE
tk_show_status=$?
if [ $tk_show_status -ne 0 ] ; then
  echo "tk failed to generate manifests"
  exit 1
fi

__DIR=$(pwd)
cd github-actions-k8s/scripts/jsonnet
echo "jsonnet-bundler updating github-actions-k8s/scripts/jsonnet"
jb update
cd $__DIR
echo "Generate Flux k8s resources"
# application is going to be used to generate the k8s resource metadata. name which must adhere to RFC 1123
# For now just look out for uppercase letters and underscores
# https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
export K8S_NAME=$(echo "$APPLICATION" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
export FILEPATH=$(realpath "$0")
export SCRIPTDIR=$(dirname $FILEPATH)
export PUSH_COMMIT='no'
echo "Running fluxification for $APPLICATION, using k8s name $K8S_NAME"
if [ -f clusters/$CLUSTER/$APPLICATION.yaml ] ; then
  tk show --ext-str application=$APPLICATION --ext-str environment=$ENVIRONMENT --ext-str oci=$OCI_ENDPOINT --ext-str k8s_name=$K8S_NAME --ext-str app_group=$APP_GROUP $SCRIPTDIR
  git diff --exit-code clusters/$CLUSTER/$APPLICATION.yaml
  if [ $? -eq 1 ] ; then
    export PUSH_COMMIT='yes'
  fi
  else
    tk show --ext-str application=$APPLICATION --ext-str environment=$ENVIRONMENT --ext-str oci=$OCI_ENDPOINT --ext-str k8s_name=$K8S_NAME --ext-str app_group=$APP_GROUP $SCRIPTDIR
  export PUSH_COMMIT='yes'
fi

if [ $PUSH_COMMIT == 'yes' ] ; then
  echo "Updating fluxcd resources for clusters/$CLUSTER/$APPLICATION.yaml"
  git config —global user.email 'CHANGEME-YOUR-BOT-EMAIL@example.com'
  git config -global user.name 'changeme-some-bot'
  # Other GHA tasks are running in parallel and we need to pull before pushing.
  git pull
  git add clusters/$CLUSTER/$APPLICATION.yaml
  git commit -m "Automated update of fluxcd resources for $ENVIRONMENT $APPLICATION by CI"
  echo "Pushing commit to git"
  git push
fi

echo "Switch to kubernetes context ${CLUSTER}"
aws eks update-kubeconfig —region 'us-east-1' —name $CLUSTER
update_context_status=$?
if [ $update_context_status -ne 0 1 ; then
  echo "Failed to switch to k8s context ${CLUSTER}"
  exit 1
fi

echo "SKIPPING: Validate k8s manifest"
# TODO - re-enable this as soon as we have self hosted GHA runner
# echo "Create namespace if it does not exist"
# kubectl create namespace $APPLICATION
# kubectl apply -f $MANIFEST_FILE -dry-run=server
# dry_run_status=$?
# if [ $dry_run_status -ne 0 ] ; then
#   echo "Detected invalid k8s yaml manifests"
#   exit 1
# fi

# List artifacts in the OCI repository tagged with the environment name
# TODO - differentiate tagged manifests from tagged container images,
#        manifests have a populated SOURCE attribute and containers do not
echo
flux list artifacts $OCI_ENDPOINT -provider aws -filter-regex $ENVIRONMENT
if [ $? -ne 0 ]; then
  echo "Failed to list OCI artifacts for $APPLICATION $ENVIRONMENT"
  echo "publish_manifest=false" >> "$GITHUB_OUTPUT"
  exit 1
fi

manifest_count=$(flux list artifacts $OCI_ENDPOINT --provider aws --filter-regex $ENVIRONMENT | grep -v '^ARTIFACT'｜wc -l）
if [ $manifest_count != "0" ]; then
  flux pull artifact $OCI_ENDPOINT:$ENVIRONMENT --provider aws -o $MANIFEST_DIR
  latest_manifest=$(stat -format='%W %n' $MANIFEST_DIR/* | tac | tail -n 1 | cut -d ' ' -f 2)
  # TODO - get rid of the following workaround
  # slap a newline on the end, dunno why but it disappears between flux push and later flux pull
  echo >> $latest_manifest
  diff --ignore-blank-lines --ignore-matching-Lines='^# ' --unified $latest_manifest $MANIFEST_FILE
  diff_status=$?

  if [ $diff_status -eq 0 ] ; then
    echo "No deployment changes"
    echo "publish_manifest=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  if [ $diff_status -ne 1] ; then
    echo "Diff Failure!!!"
    echo "publish _manifest=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

fi

# Either there was a valid diff, or there is not a manifest for the environment yet.
echo "Updated Manifests need to be deployed"
echo "publish_manifest=true" >> "$GITHUB_OUTPUT"
exit 0

