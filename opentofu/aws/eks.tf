# Create the IAM role for the EBS CSI Driver via IRSA
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "${var.cluster_name}-ebs-csi-driver-role"

  # Automatically attaches the AWS managed policy: arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26.0"

  # The "cluster_" prefix was removed in v21
  name               = var.cluster_name
  kubernetes_version = "1.36"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # The "cluster_" prefix was removed in v21
  endpoint_public_access = true

  # enable_irsa = true (REMOVED: EKS Pod Identity is now the default)

  # Grants your local AWS CLI user administrative access to the cluster via Access Entries
  enable_cluster_creator_admin_permissions = true

  # Explicitly provision networking addons BEFORE the nodes - fix for "NetworkPluginNotReady"
  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent    = true
      before_compute = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default_node_group = {
      min_size     = 2
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      # --- Fix for "invalid capacity 0 on image filesystem" ---
      ami_type  = "AL2023_x86_64_STANDARD"
      disk_size = 40
    }
  }

  node_security_group_additional_rules = {
    ingress_istio_webhook = {
      description                   = "Allow EKS Control Plane to reach Istio Webhook"
      protocol                      = "tcp"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}