terraform {
  # 한국어 주석: On-Premise 앱 외부 리소스는 Kubernetes manifest와 분리된 state로 관리합니다.
  required_version = ">= 1.11.0"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "harbor" {
  # 한국어 주석: HARBOR_URL, HARBOR_USERNAME, HARBOR_PASSWORD 환경 변수로도 주입할 수 있습니다.
  url      = var.harbor_url
  username = var.harbor_username
  password = var.harbor_password
  insecure = var.harbor_insecure
}

provider "vault" {
  # 한국어 주석: VAULT_ADDR, VAULT_TOKEN 환경 변수로도 주입할 수 있습니다.
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = var.vault_skip_tls_verify
}
