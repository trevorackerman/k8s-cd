local ploopy = import '../../../common-libsonnet/ploopy.libsonnet';
local application_name = 'example';

{
  'example': ploopy.Application {
    name: application_name, // TODO update to figure this out via reflection
    type: 'job',
    node_flavor: 'compute-intensive', // node with specific compute requirements to run jobs on
    job+: {
      indexed: true,
      array_size: 4,
      parallelism: 4,
    },
    containers: {
      [application_name]: {
        image: '',
        command: '/bin/bash',
        args: ['-c', 'echo "My partition: ${J0B_COMPLETION_INDEX}" && run-array-job -config_file s3://some_bucket/some_asset']
        env_vars: {
          API_HOST: {
            secretKeyRef: {
              name: application_name, // TODO - if possible derive the secret name from the application name
              key: 'API_HOST',
            },
          },
          API_TOKEN: {
            secretKeyRef: {
              name: application_name, // TODO - if possible derive the secret name from the application name
              key: 'API_TOKEN',
           },
         },
       },
       resources: {
         requests: {
           memory: '2Gi',
           cpu: '2',
         }
         limits: {
           memory: '2Gi',
           cpu: '2',
         },
       },
     },
   },
 },
}

