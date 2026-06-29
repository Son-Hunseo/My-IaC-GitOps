data "aws_availability_zones" "available" {
  # 한국어 주석: 사용 가능한 AZ만 조회해 기본 subnet 배치를 안정적으로 구성합니다.
  state = "available"
}

data "aws_caller_identity" "current" {
  # 한국어 주석: account ID가 필요한 IAM policy ARN 범위를 현재 실행 계정에 맞춰 계산합니다.
}

locals {
  # 한국어 주석: 명시된 AZ가 있으면 그대로 사용하고, 없으면 필요한 subnet 수만큼 현재 region의 AZ를 선택합니다.
  subnet_count                     = max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs))
  selected_azs                     = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, local.subnet_count)
  common_name_prefix               = var.cluster_name
  oidc_provider_url_without_scheme = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
  external_secrets_secret_arns     = length(var.external_secrets_secret_arns) > 0 ? var.external_secrets_secret_arns : ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}-*"]
}

resource "aws_vpc" "this" {
  # 한국어 주석: EKS control plane과 worker node가 사용할 전용 VPC입니다.
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.common_name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  # 한국어 주석: public subnet과 NAT Gateway의 인터넷 경로를 제공합니다.
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.common_name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = {
    for index, cidr in var.public_subnet_cidrs : index => cidr
  }

  # 한국어 주석: public subnet은 NAT Gateway를 배치하고 외부 인터넷 경로를 제공하는 네트워크 영역입니다.
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = local.selected_azs[tonumber(each.key)]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.common_name_prefix}-public-${tonumber(each.key) + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    for index, cidr in var.private_subnet_cidrs : index => cidr
  }

  # 한국어 주석: private subnet은 EKS worker node의 기본 배치 위치입니다.
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = local.selected_azs[tonumber(each.key)]

  tags = {
    Name                              = "${local.common_name_prefix}-private-${tonumber(each.key) + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  # 한국어 주석: public subnet은 Internet Gateway로 기본 route를 보냅니다.
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.common_name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  # 한국어 주석: 각 public subnet을 public route table에 연결합니다.
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = var.single_nat_gateway ? { "0" = "single" } : {
    for index, subnet in aws_subnet.public : index => subnet.id
  }

  # 한국어 주석: NAT Gateway용 Elastic IP입니다. destroy 시 함께 제거됩니다.
  domain = "vpc"

  tags = {
    Name = "${local.common_name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "this" {
  for_each = aws_eip.nat

  # 한국어 주석: private subnet의 outbound 인터넷 접근을 제공합니다. worker node 이미지 pull 등에 필요합니다.
  allocation_id = each.value.id
  subnet_id     = var.single_nat_gateway ? aws_subnet.public["0"].id : aws_subnet.public[each.key].id

  tags = {
    Name = "${local.common_name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  # 한국어 주석: single NAT 모드에서는 모든 private subnet이 첫 NAT Gateway를 공유합니다.
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this["0"].id : aws_nat_gateway.this[each.key].id
  }

  tags = {
    Name = "${local.common_name_prefix}-private-rt-${tonumber(each.key) + 1}"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  # 한국어 주석: 각 private subnet을 해당 private route table에 연결합니다.
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_security_group" "cluster" {
  # 한국어 주석: EKS control plane에 추가로 연결할 security group입니다.
  name        = "${local.common_name_prefix}-cluster-sg"
  description = "Additional security group for EKS control plane"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow outbound traffic from EKS control plane"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.common_name_prefix}-cluster-sg"
  }
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  # 한국어 주석: EKS service가 cluster role을 수임할 수 있도록 trust policy를 구성합니다.
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  # 한국어 주석: EKS control plane이 AWS 리소스를 제어하는 데 사용하는 IAM role입니다.
  name               = "${local.common_name_prefix}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  # 한국어 주석: EKS control plane에 필요한 AWS 관리형 정책을 연결합니다.
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  # 한국어 주석: Kubernetes workload 배포는 하지 않고 control plane 자체만 생성합니다.
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(values(aws_subnet.public)[*].id, values(aws_subnet.private)[*].id)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # 한국어 주석: Terraform 실행 주체에게 cluster admin 접근을 부여해 초기 운영 확인이 가능하도록 합니다.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  # 한국어 주석: EC2 worker node가 node role을 수임할 수 있도록 trust policy를 구성합니다.
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  # 한국어 주석: EKS managed node group의 EC2 인스턴스가 사용하는 IAM role입니다.
  name               = "${local.common_name_prefix}-${var.node_group_name}-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  # 한국어 주석: worker node가 EKS cluster에 join하는 데 필요한 정책입니다.
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  # 한국어 주석: 기본 VPC CNI가 ENI와 IP 주소를 관리하는 데 필요한 정책입니다.
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  # 한국어 주석: worker node가 Amazon ECR 이미지를 pull할 수 있도록 읽기 권한을 부여합니다.
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = toset(var.additional_node_policy_arns)

  # 한국어 주석: 환경별 추가 node 권한이 필요한 경우 명시적으로 연결합니다.
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "default" {
  # 한국어 주석: managed node group은 private subnet에 배치하며 기본 worker 수는 2대입니다.
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = values(aws_subnet.private)[*].id

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size_gb

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "worker"
  }

  tags = {
    Name = "${local.common_name_prefix}-${var.node_group_name}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry,
    aws_iam_role_policy_attachment.node_additional,
  ]
}

data "tls_certificate" "eks_oidc" {
  # 한국어 주석: EBS CSI Driver가 IRSA로 AWS API를 호출할 수 있도록 EKS OIDC issuer의 thumbprint를 조회합니다.
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  # 한국어 주석: Kubernetes ServiceAccount와 IAM Role을 연결하기 위한 EKS OIDC provider입니다.
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  # 한국어 주석: aws-ebs-csi-driver controller ServiceAccount만 이 role을 수임할 수 있게 제한합니다.
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  # 한국어 주석: EBS CSI Driver가 EBS volume을 생성/삭제/attach하기 위한 IAM role입니다.
  name               = "${local.common_name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  # 한국어 주석: AWS 관리형 EBS CSI Driver 권한을 연결합니다.
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  # 한국어 주석: 플랫폼 PVC가 gp3 EBS volume으로 동적 프로비저닝되도록 EBS CSI Driver를 설치합니다.
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.default,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  # 한국어 주석: kube-system/aws-load-balancer-controller ServiceAccount만 이 role을 수임할 수 있게 제한합니다.
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_without_scheme}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_without_scheme}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  # 한국어 주석: AWS Load Balancer Controller가 ALB/NLB 관련 AWS API를 호출하기 위한 IRSA role입니다.
  name               = "${local.common_name_prefix}-aws-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  # 한국어 주석: AWS Load Balancer Controller v3.4.0 공식 설치 문서의 reference IAM policy입니다.
  name        = "${local.common_name_prefix}-aws-lbc-policy"
  description = "IAM policy for AWS Load Balancer Controller on ${var.cluster_name}."
  policy      = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  # 한국어 주석: controller ServiceAccount용 IRSA role에 ALB/NLB 관리 권한을 연결합니다.
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

data "aws_iam_policy_document" "external_secrets_assume_role" {
  # 한국어 주석: external-secrets/external-secrets ServiceAccount만 이 role을 수임할 수 있게 제한합니다.
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_without_scheme}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_without_scheme}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  # 한국어 주석: External Secrets Operator가 AWS Secrets Manager 값을 읽기 위한 IRSA role입니다.
  name               = "${local.common_name_prefix}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
}

data "aws_iam_policy_document" "external_secrets" {
  # 한국어 주석: dataFrom, find 같은 조회 기능에 필요한 Secrets Manager listing 권한입니다.
  statement {
    actions = [
      "secretsmanager:ListSecrets",
      "secretsmanager:BatchGetSecretValue",
    ]
    resources = ["*"]
  }

  # 한국어 주석: 기본값은 cluster_name prefix의 secret만 읽도록 제한하며, 변수로 더 좁히거나 넓힐 수 있습니다.
  statement {
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = local.external_secrets_secret_arns
  }

  dynamic "statement" {
    for_each = length(var.external_secrets_kms_key_arns) > 0 ? [1] : []

    content {
      actions   = ["kms:Decrypt"]
      resources = var.external_secrets_kms_key_arns
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  # 한국어 주석: External Secrets Operator의 AWS Secrets Manager read 권한을 IRSA role에 연결합니다.
  name        = "${local.common_name_prefix}-external-secrets-policy"
  description = "IAM policy for External Secrets Operator on ${var.cluster_name}."
  policy      = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  # 한국어 주석: External Secrets Operator ServiceAccount용 IRSA role에 Secrets Manager 읽기 권한을 연결합니다.
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}
