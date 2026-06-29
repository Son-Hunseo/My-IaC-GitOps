terraform {
  # 한국어 주석: EKS와 VPC 리소스 구성을 위해 Terraform 1.6 이상을 사용합니다.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      # 한국어 주석: AWS provider는 VPC, IAM, EKS, EC2 태그를 모두 관리합니다.
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      # 한국어 주석: EKS OIDC issuer 인증서 thumbprint를 조회해 IRSA provider를 구성합니다.
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  # 한국어 주석: 인증 정보는 AWS_PROFILE, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, OIDC role 등 표준 AWS 방식으로 주입합니다.
  region = var.aws_region

  default_tags {
    # 한국어 주석: 모든 AWS 리소스에 공통 태그를 부여해 소유권과 환경 구분을 쉽게 합니다.
    tags = var.default_tags
  }
}
