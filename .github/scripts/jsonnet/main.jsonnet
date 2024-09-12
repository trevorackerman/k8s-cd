local f = import './fluxification.libsonnet';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  flux: f.fluxification.new(
    k8s_application_name=std.extVar('k8s_name'),
    flux_namespace='example',
    oci_url=std.extVar('oci'),
    ref_tag=std.extVar('environment'),
    environment=std.extVar('environment'),
    application_name=std.extVar('application'),
    domain=std.extVar('domain'),
  ),
}

