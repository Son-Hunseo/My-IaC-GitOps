output "cluster_name" {
  # 한국어 주석: 후속 bootstrap 또는 운영 명령에서 사용할 EKS cluster 이름입니다.
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  # 한국어 주석: EKS API endpoint를 확인하기 위한 출력입니다.
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  # 한국어 주석: kubeconfig 생성에 필요한 CA 데이터이며 민감 출력으로 취급합니다.
  description = "Base64 encoded EKS cluster certificate authority data."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "vpc_id" {
  # 한국어 주석: 후속 네트워크 연동이나 보안 점검에서 사용할 VPC ID입니다.
  description = "VPC ID used by EKS."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  # 한국어 주석: NAT Gateway와 public route table에 연결된 public subnet 목록입니다.
  description = "Public subnet IDs used by the EKS VPC."
  value       = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  # 한국어 주석: managed worker node가 배치되는 private subnet 목록입니다.
  description = "Private subnet IDs used by EKS worker nodes."
  value       = values(aws_subnet.private)[*].id
}

output "node_group_name" {
  # 한국어 주석: managed node group 확인 및 운영 명령에 사용할 이름입니다.
  description = "Managed node group name."
  value       = aws_eks_node_group.default.node_group_name
}

output "node_group_role_arn" {
  # 한국어 주석: 후속 인프라 계층이 node role 권한을 확장해야 할 때 참조할 ARN입니다.
  description = "IAM role ARN used by EKS worker nodes."
  value       = aws_iam_role.node.arn
}

output "ebs_csi_role_arn" {
  # 한국어 주석: EBS CSI Driver add-on이 사용하는 IRSA role ARN입니다.
  description = "IAM role ARN used by the Amazon EBS CSI Driver add-on."
  value       = aws_iam_role.ebs_csi.arn
}

output "aws_load_balancer_controller_role_arn" {
  # 한국어 주석: 03-k8s-clusters AWS Load Balancer Controller values에 넣을 IRSA role ARN입니다.
  description = "IAM role ARN used by AWS Load Balancer Controller."
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "external_secrets_role_arn" {
  # 한국어 주석: 03-k8s-clusters External Secrets Operator values에 넣을 IRSA role ARN입니다.
  description = "IAM role ARN used by External Secrets Operator."
  value       = aws_iam_role.external_secrets.arn
}

output "update_kubeconfig_command" {
  # 한국어 주석: cluster 접근 확인용 명령이며 Kubernetes 리소스 배포는 수행하지 않습니다.
  description = "Command for configuring local kubectl access after apply."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
