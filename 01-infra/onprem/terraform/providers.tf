terraform {
  # 한국어 주석: Terraform 버전은 안정적인 provider 기능을 사용할 수 있도록 1.6 이상으로 제한합니다.
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      # 한국어 주석: bpg/proxmox provider는 Proxmox VE API 기반 VM 생성과 cloud-init 초기화를 지원합니다.
      source  = "bpg/proxmox"
      version = "~> 0.70"
    }
  }
}

provider "proxmox" {
  # 한국어 주석: endpoint와 API token은 환경별 값이므로 변수로만 주입합니다.
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"

  # 한국어 주석: 자체 서명 인증서를 사용하는 사내 Proxmox 환경을 위해 검증 비활성화를 선택 가능하게 둡니다.
  insecure = var.proxmox_insecure
}

