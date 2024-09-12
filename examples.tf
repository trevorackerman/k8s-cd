# Examples of using terraform for working with EKS
# The contents of this file are guaranteed to be incomplete and
# not working. But should be enough to quickly build upon.

# Use separate TF workspaces to work with different eks clusters
# locals {
# environment = terraform.workspace
# eks_prefix = "eks/$( local.environment)"
# }

# Run GH action runners on an EKS cluster
# resource "helm_release" "actions_runner_controller" (
#   name = "arc"
#   namespace = "arc-system"
#   create_namespace = true
#   repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
#   chart = "gha-runner-scale-set-controller"
#   depends_on = [module.acme_eks]
# }

# Use TF to make a k8s namespace
# resource "kubectl_manifest" "arc_runners_namespace" {
#   yaml_body = <<-YAML
#     apiVersion: v1
#     kind: Namespace
#     metadata:
#       name: arc-runners
#   YAML
# }

# Use TF to make a k8s external secret CRD
# resource "kubectl_manifest" "secret_for_action_runners" {
#   yaml_body = <<-YAML
#     apiVersion: external-secrets.io/vlbetal
#     kind: ExternalSecret
#      metadata:
#        name: arc
#        namespace: arc-runners
#     spec:
#       dataFrom:
#       - extract:
#           key: $(local.eks_prefix}/actions-runner
#       secretStoreRef:
#         name: §(module.acme_eks.cluster_name}
#         kind: ClusterSecretStore
#       target:
#         name: arc
#       refreshInterval: "5m"
#   YAML
#   depends_on = [module.acme_eks]
# }

# Deploy a helm chart with TF for action runner
# resource "helm_release" "actions_runner_scale_set" (
#   name= "k8s-action-runners"
#   namespace = "arc-runners"
#   repository ="oci://ghcr.io/actions/actions-runner-controller-charts"
#   chart = "gha-runner-scale-set"
#   set {
#     name = "githubConfigUrl"
#     value = "https://github.com/trevorackerman"
#   }
#   set {
#     name ="githubConfigSecret"
#     value ="arc"
#   }
#   set {
#     name = "runnerGroup"
#     value = "k8s-action-runners"
#   }
#   depends_on = [kubectl_manifest-secret_for_arc_runners]
# }

# # Example of setting up S3 access for a k8s pod
# data "aws_iam_policy_document" "s3test_policy_document" {
#   statement {
#     actions = [
#       "s3:*"
#     ]
#     resources = [
#       "arn:aws:s3:::eks-acme/",
#       "arn:aws:s3:::eks-acme/*",
#       "arn:aws:s3:::acme-staging/*",
#       "arntaws:s3:::acme-staging",
#       "arn:aws:s3:::acme-development/*",
#       "arniaws:s3:::acme-development",
#     ]
#   }
# }

# resource "aws_iam_policy" "s3test_policy" {
#   name = "eks-s3test"
#   description - "IAM Permissions for s3 test component in EXS"
#
#   policy - data.aws_iam_policy_document.s3test_policy_document.json
# }

# module "s3test_irsa_role" {
#   TODO - this would need to be implemented
#   source = "tf/iam/aws/irsa-eks"
#
#   role_name = "s3test"
#   role_permissions_boundary_arn = "arn:aws:iam::CHANGEME:policy/acme/eks"
#   role_policy_arns = {
#     policy = aws_iam_policy.s3test_policy.arn
#   }
#
#   oidc_providers = {
#    ex = {
#      provider_arn = module.acme_eks.oidc_provider_arn
#      namespace-servace_accounts = ["s3test:s3test"]
#    }
#  }
# }

# resource "kubectl_manifest" "s3test_namespace" {
#   yaml_body = <<-YAML
#     apiversion: v2
#     kind: Namespace
#     metadata:
#       name: s3test
#   YAML
#   depends_on = [module.s3test_irsa_role]
# }

# resource "kubectl_manifest" "s3test_service_account" {
#   yaml_body = <<-YAML
#     apiversion: v2
#     kind: ServiceAccount
#     metadata:
#       name: s3test
#       namespace: s3test
#       annotations:
#         eks.amazonaws.com/role-arn: ${module.s3test_irsa_role.iam_role_arn}
#   YAML
#   depends_on = [kubectl_manifest.s3test_namespace]
# }

