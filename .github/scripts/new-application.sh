#!/usr/bin/env bash

set -eux

APPLICATION=$1
# Generate a string we can use in the jsonnet files
# this also impacts names of libsonnet files
# e.g. Can't use
# foo-bar: ( ... }
# Need to use
# foo_bar: { ... }
# TODO - obviously need to handle more than just hyphen characters
APPLICATION_SLUG=$(echo $APPLICATION | sed -e 's/-/_/g')

# Check if the directory exists and contains only a README.md file
if [ -d "applications/$APPLICATION" ] && [ "$(1s -A applications/$APPLICATION | wc -1)" -eq 1 ] && [ -f "applications/$APPLICATION/README.md" ]; then
  pushd applications/$APPLICATION
  tk init -f --k8s 1.27
  rm -r environments
else
  echo "Directory applications/$APPLICATION either doesn't exist or contains files other than README.d. Exiting..."
  exit 1
fi

jb install github.com/grafana/jsonnet-libs/tanka-util
jb install ../../common-libsonnet
jb update

echo "OCI_REPOSITORY=path/to/ecr_image/$(APPLICATION}" > .env

cat << EOF > lib/config.libsonnet
{
  _cfg+:: {
    name: "$APPLICATION", // will be the namespace and also the name of various k8s resources used by the application
    app_group: 'example',
    container: {
      image: '',
      command: '/bin/bash',
      args: ['-c', 'echo "New application running!"'],
      // environment variables that are to be set; remove or set to {} if not needed
      env_vars: {
        ENV_VAR1: 'valuel',
      },
      // external secrets that are to be set as environment variables; remove or set to {} if not needed
      env_vars_from_secrets: {
        SECRET1: {
          secretKeyRef: {
            name: $._cfg.name,
            key: 'SECRET1',
          },
        },
      },
    },
    job: {
      arraySize: '', // total number of jobs to complete
      parallelism: '', // job parallelism
      resources: {
        requests: {
          memory: '', // memory request in Gi, remove entry if not needed
          cpu: '', // cpu request, remove entry if not needed
        },
        limits: {
          memory: '', // memory limit in Gi, remove entry if not needed
          cpu: '', // cpu limit, remove entry if not needed
        },
      },
      node_flavor: 'modeling', // node with specific compute requirements to run jobs on
    },
  },
}
EOF

# TODO - replace the common-libsonnet import with the actual repo
cat << EOF > Lib/$APPLICATION_SLUG.libsonnet
local example = import '../../../common-libsonnet/example.libsonnet';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

// force build
(import './config.libsonnet') +
{
  // aliases
  local cfg = $._cfg,

  namespace: k.core.vl.namespace.new(cfg.name),
  serviceAccount: k.core.vl.serviceAccount.new(cfg.name)
                  + k.core.v1.serviceAccount.metadata.withNamespace(cfg.name)
                  + k.core.v1.serviceAccount.metadata.withAnnotations({
                    'eks.amazonaws.com/role-arn': 'arn:aws:iam::CHANGEME:role/eks-' + cfg.environment +'-' + cfg.app_group + '-' + cfg.name,
                  }),
  application: acme.application.new(cfg.name, cfg. container.image, cfg.container.env_vars_from_secrets + cfg.container.env_vars)
           + acme.application.withContainerCommand(cfg.container.command)
           + acme.application.withContainerArgs(cfg.container.args)
           + acme.application.withResourceRequests(cfg.job.resources. requests)
           + acme.application.withResourceLimits(cfg.job.resources.limits)
           + acme.application.withIndexedJob(cfg-job.node_flavor, cfg-job.arraySize, cfg-job. parallelism)
           + acme.application.withExternalSecret(
             cfg.environment + '-' + cfg.app_group,
             'eks/' + cfg.environment + /' + cfg.app_group + */' + cfg.name,
             cfg.name
           ),
}
EOF

popd
echo "New files for $APPLICATION"
find applications/APPLICATION | grep -v vendor
echo

echo "jsonnetfile.json for $APPLICATION"
cat applications/$APPLICATION/jsonnetfile.json
echo
echo NEW APPLICATION BOILERPLATE DONE FOR $APPLICATION

