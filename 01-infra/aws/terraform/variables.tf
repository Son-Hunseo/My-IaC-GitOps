variable "aws_region" {
  # 한국어 주석: 기본 region은 서울 리전이며 환경에 맞게 변경할 수 있습니다.
  description = "AWS region where the EKS infrastructure will be created."
  type        = string
  default     = "ap-northeast-2"
}

variable "default_tags" {
  # 한국어 주석: 모든 AWS 리소스에 적용할 프로젝트 식별용 공통 태그입니다.
  description = "Default tags applied to all supported AWS resources."
  type        = map(string)
  default = {
    Project = "My-IaC-GitOps"
  }
}

variable "cluster_name" {
  # 한국어 주석: VPC 태그, IAM role 이름, EKS cluster 이름에 함께 사용되는 핵심 식별자입니다.
  description = "EKS cluster name."
  type        = string
  default     = "gitops-eks"
}

variable "cluster_version" {
  # 한국어 주석: 지원 종료 비용을 피하기 위해 기본값은 현재 EKS standard support 버전을 사용합니다.
  description = "EKS Kubernetes version for the control plane."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  # 한국어 주석: EKS cluster 전용 VPC 주소 대역입니다.
  description = "CIDR block for the EKS VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidrs" {
  # 한국어 주석: public subnet은 NAT Gateway와 인터넷 경로에 사용됩니다.
  description = "Public subnet CIDR blocks. At least two subnets in different AZs are recommended for EKS."
  type        = list(string)
  default     = ["10.40.0.0/20", "10.40.16.0/20"]
}

variable "private_subnet_cidrs" {
  # 한국어 주석: private subnet은 EKS worker node 기본 배치 위치입니다.
  description = "Private subnet CIDR blocks used by EKS nodes. At least two subnets in different AZs are recommended."
  type        = list(string)
  default     = ["10.40.32.0/20", "10.40.48.0/20"]
}

variable "availability_zones" {
  # 한국어 주석: 비워 두면 AWS provider가 조회한 사용 가능 AZ를 순서대로 사용합니다.
  description = "Availability zones used by subnets. Leave empty to use the first available AZs in the selected region."
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  # 한국어 주석: 비용 절감을 위해 개발 환경에서는 단일 NAT Gateway를 기본값으로 둡니다.
  description = "Use one NAT Gateway for all private subnets. Safer cost default for non-production environments."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  # 한국어 주석: 로컬 운영자가 EKS API에 접근해야 하는 초기 환경을 고려해 public endpoint를 허용합니다.
  description = "Enable public access to the EKS API endpoint."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  # 한국어 주석: VPC 내부 자동화나 bastion에서 API에 접근할 수 있도록 private endpoint도 허용합니다.
  description = "Enable private VPC access to the EKS API endpoint."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  # 한국어 주석: 실제 환경에서는 관리자 공인 IP 대역으로 제한해야 합니다.
  description = "CIDR ranges allowed to access the public EKS API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_group_name" {
  # 한국어 주석: managed node group의 논리 이름입니다.
  description = "EKS managed node group name."
  type        = string
  default     = "default-workers"
}

variable "node_instance_types" {
  # 한국어 주석: 요구사항에 맞춰 t3.medium worker node를 기본값으로 사용합니다.
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  # 한국어 주석: 요구사항에 맞춰 worker node 2대를 desired size로 설정합니다.
  description = "Desired worker node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  # 한국어 주석: 기본 구성에서는 항상 worker node 2대를 유지합니다.
  description = "Minimum worker node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  # 한국어 주석: 기본 구성에서는 자동 확장을 열어 두지 않고 2대로 고정합니다.
  description = "Maximum worker node count."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  # 한국어 주석: managed node group root volume 크기입니다.
  description = "Root volume size for EKS managed worker nodes."
  type        = number
  default     = 50
}

variable "node_capacity_type" {
  # 한국어 주석: 재현 가능한 기본 환경을 위해 ON_DEMAND를 기본값으로 둡니다.
  description = "Capacity type for the managed node group. Valid values are ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "additional_node_policy_arns" {
  # 한국어 주석: 스토리지나 관측 도구 등 후속 계층에서 node role 권한이 필요할 때 명시적으로 확장합니다.
  description = "Additional IAM policy ARNs attached to the EKS node role."
  type        = list(string)
  default     = []
}

variable "ebs_csi_addon_version" {
  # 한국어 주석: 비워 두면 AWS가 클러스터 버전에 맞는 기본 EBS CSI add-on 버전을 선택합니다.
  description = "Optional version for the aws-ebs-csi-driver EKS add-on. Leave null to use the AWS default for the cluster version."
  type        = string
  default     = null
}

variable "external_secrets_secret_arns" {
  # 한국어 주석: External Secrets Operator가 읽을 수 있는 Secrets Manager secret ARN 목록입니다.
  description = "Secrets Manager secret ARNs readable by External Secrets Operator. Defaults to secrets prefixed with cluster_name."
  type        = list(string)
  default     = []
}

variable "external_secrets_kms_key_arns" {
  # 한국어 주석: 고객 관리형 KMS key로 암호화된 secret을 읽을 때 필요한 decrypt 대상 key ARN 목록입니다.
  description = "Optional KMS key ARNs that External Secrets Operator can decrypt for Secrets Manager secrets."
  type        = list(string)
  default     = []
}
