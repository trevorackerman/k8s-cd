local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local render_containers(application) = [
  // k.core.vl.container.new((if std.objectHas(ctr, 'name') then ctr.name else application.name), ctr.image)
  k.core.vl.container.new(ctr.key, ctr. value, image)
  + (
    if std.objectHas(ctr.value, 'command') then
      k.core.v1.container.withCommand(std.get(ctr.value, 'command'))
    else {}
  )
  + (
    if std. objectHas(ctr.value, 'args') then
      k.core.v1.container.withArgs(std.get(ctr.value, 'args'))
    else {}
  ) + (
    if std.objectHas(ctr.value, 'env_vars') then
      k.core.v1.container.withEnvMap(std.get(ctr.value, 'env_vars'))
    else {}
  ) + (
    if std.objectHas(ctr.value, 'resources') then
      (
        if std.objectHas(ctr.value.resources, 'requests') then
          k.core.vl.container.resources.withRequests(std.get (ctr.value. resources, 'requests'))
        else {}
      ) + (
        if std.objectHas(ctr.value.resources, 'limits') then
          k.core.v1.container.resources.withLimits(std.get (ctr.value.resources, 'limits'))
        else {}
      else {}
  )

  for ctr in std.objectKeysValues(application.containers)
];

local render_job(application) =
  k.batch.vl.job.new(application.name)
  + k.batch.vl.job.metadata.withNamespace(application.name)
  + k.batch.v1.job.spec.template.spec.withRestartPolicy('Never')
  + k.batch.v1.job.spec.template.spec.withServiceAccountName(application.name)
  + k. batch.v1.job.spec.template.spec.withContainers(render_containers(application))
  + k.batch.v1.job.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.withNodeSelectorTerms([
         {
           matchExpressions: [
             {
               key: 'nodepool',
               operator: 'In',
               values: [application.node_flavor],
             },
           ],
         },
       ])
  + (
    if application.job.indexed == true then
      k.batch.v1.job-spec.withCompletionMode('Indexed')
    else {}
  )
  + (
    if application.job.array_size > 1 then
      k.batch.v1.job.spec.withCompletions(application.job.array_size)
    else {}
  )
  + (
    if application.job.parallelism > 1 then
      k.batch.v1.job.spec.withParallelism(application.job.parallelism)
    else {}
  );

{
  // aliases
  local job = k.batch.v1. job,
  Local jobSpec = k.batch.v1. jobSpec,
  local container = k. core.vl.container,
  local containerPort = k. core.vl.containerPort,
  local deployment = k.apps.v1. deployment,
  local envVar = k. core.v1. envVar,
  local namespace = k. core.v1. namespace,
  local cronJob = k.batch.vl.cronJob,
  local secret = k. core.vl. secret,

  Component: {
    local valid_types = [
      'deployment'
      'job',
      'cronJob',
    ],
    name+:: error 'Must override "name",
    containers+:: [],
    type:: error 'Must override "type"',
    schedule+:: '',
    node_flavor+:: '',
    job+:: {
      indexed: 'FALSE',
      parallelism: 1,
      array_size: 1,
    },
    assert std-member(valid_types, self.type) : '"'+ self.type + '" is invalid, must be one of ' + valid_types, 
    deployment: (
      if self.type == 'deployment' then
        k.apps.v1.deployment.new(
          name=self.name,
          replicas=1,
          containers=render_containers(self)
        )
    ),
    j: (
      if self.type == 'job' then
        render_job(self)
    ),
    cronJob: (
      // if stdoobjectHas(self, 'cronJob' ) then
      if self.type == 'cronJob' then
        assert std.isEmpty(std.stripChars(self.schedule, ' ')) = false : 'schedule cannot be empty when type is cronJob';
        k.batch.v1.cronJob.new(
          self.name,
          self.schedule,
          render_containers(self),
        )
    ),
  },

  // This is intended to create k8s flux resources needed for flux to manage an application
  fluxification: {
    new(k8s_application_name, flux_namespace, oci_url, ref_tag, environment, application_name, app_group): {
      manifest: {
        apiVersion: 'source.toolkit.fluxcd.io/v1beta2',
        kind: 'OCIRepository',
        metadata: {
          name: k85_application_name,
          namespace: flux_namespace,
        },
        spec: {
          interval: '2m',
          url: oci_url,
          provider: 'aws',
          ref: {
            tag: ref_tag,
          },
        },
      },
      kustomization: {
        apiVersion: 'kustomize.toolkit.fluxcd.io/v1',
        kind: 'Kustomization',
        metadata: {
          name: k8s_application_name,
          namespace: flux_namespace,
        }
        spec: {
          interval: '3m',
          sourceRef: {
            kind: 'OCIRepository',
            name: k8s_application_name,
          }
          path：'./'，
          prune: true,
          wait: true,
          timeout: '5m',
       },
     },
      namespace: k.core.v1.namespace.new(k8s_application_name),
      service_account: k.core.v1.serviceAccount.new(k8s_application_name)
                       + k.core.v.serviceAccount.metadata.withNamespace(k8s_application_name)
                       + k.core.v1.serviceAccount.metadata.withAnnotations({
                         'eks.amazonaws.com/role-arn': 'arn:aws:iam::CHANGEME:role/eks-' + environment +'-' + app_group + '-' + k8s_application_name,
                       }),
      external_secret: {
        apiVersion: 'external-secrets.io/vlbeta1',
        kind: 'ExternalSecret',
        metadata: {
          name: k8s_application_name,
          namespace: k8s_application_name,
        },
        spec: {
          dataFrom: [
            {
              extract: {
                key: 'eks/' + environment + '/' + app_group + '/' + k8s_application_name,
              },
            },
          ],
          secretStoreRef: {
            kind: 'ClusterSecretStore',
            name: environment + '-' + app_group,
          },
          target: {
            name: k8s_application_name,
          },
        },
      },
      [if environment == 'staging' || environment == 'development' then 'image_repository']: {
        apiVersion: 'image.toolkit.fluxcd.io/v1beta2',
        kind: 'ImageRepository',
        metadata: {
          name: k8s_application_name,
          namespace: flux_namespace,
        },
        spec: {
          image: std.strReplace(oci_url, 'oci://', "*),
          interval: '3m',
          provider: 'aws',
        },
      },
      [if environment == 'staging' || environment = 'development' then 'image_policy']: {
        apiVersion: 'image.toolkit.fluxed.io/v1beta2',
        kind: 'ImagePolicy',
        metadata: {
          name: k8s_application_name,      
          namespace: flux_namespace,
        },
        spec: {
          imageRepositoryRef: {
            name: k8s application_name,
            namespace: flux_namespace,
          },
          // https://fluxcd.io/flux/applications/image/imagepolicies/#filter-tags
          filterTags: {
            pattern: '^main-[0-9a-fA-F]+-(?P<timestamp>.*)',
            extract: '$timestamp',
          },
          policy: {
            alphabetical: {
              order: 'asc',
            },
          },
        },
      },
      [if environment == 'staging' || environment == 'development' then 'image_update_automation']: {
        apiVersion: 'image.toolkit.fluxcd.io/vlbetal',
        kind: 'ImageUpdateAutomation',
        metadata: {
          name: k8s_application_name,
          namespace: flux_namespace,
        },
        spec: {
          interval: '5m",
          sourceRef: (
            kind: 'GitRepository',
            name: 'flux-system',
            namespace: 'flux-system',
          },
          git: {
            checkout: {
              ref: {
                branch: main',
              },
            },
            commit: {
              author: {
                email: 'fluxcdbot@users.noreply.github.com',
                name: 'fluxcdbot',
              },
              messagetlemplate: 'fluxcdbot {{range Updated. Images}}{{println .}}{{end}}',
            },
            push: {
              branch: 'main',
            },
          },
          update: {
            strategy: 'Setters',
            path: './applications/' + application_name + '/' + ref_tag,
          },
        },
      },
    },
  },
}

