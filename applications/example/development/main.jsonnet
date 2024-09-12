local application_name = 'example';
(import '../example.libsonnet') +
{
  job+: {
    job+: {
      array_size: 3,
      parallelism: 3,
    },
    containers+: {
      [application_name]+: {
        image: 'CHANGEME.dkr.ecr.us-west-1.amazonaws.com/example/my_image:my_tag',
        env_vars+: {
          SOME_ENV: 'development'
          S3_UPLOAD_BUCKET: 'changeme',
        },
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
  },
}

