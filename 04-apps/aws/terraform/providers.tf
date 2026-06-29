terraform {
  # 한국어 주석: 앱별 AWS 리소스는 EKS 본체와 분리된 state로 관리합니다.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # 한국어 주석: 인증 정보는 AWS_PROFILE, AWS_ACCESS_KEY_ID, OIDC role 등 표준 AWS 방식으로 주입합니다.
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}
