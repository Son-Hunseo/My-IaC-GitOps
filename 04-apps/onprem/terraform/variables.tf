variable "harbor_url" {
  # 한국어 주석: Harbor API endpoint입니다. 예: https://harbor.onprem.arpa
  description = "Harbor URL."
  type        = string
}

variable "harbor_username" {
  # 한국어 주석: Harbor project를 만들 수 있는 bootstrap 계정입니다.
  description = "Harbor username."
  type        = string
  sensitive   = true
}

variable "harbor_password" {
  # 한국어 주석: Harbor 계정 password 또는 token입니다.
  description = "Harbor password."
  type        = string
  sensitive   = true
}

variable "harbor_insecure" {
  # 한국어 주석: 내부 CA를 신뢰하지 않는 로컬 환경에서만 true로 둡니다.
  description = "Skip Harbor TLS verification."
  type        = bool
  default     = true
}

variable "vault_address" {
  # 한국어 주석: Vault API endpoint입니다. 예: https://vault.onprem.arpa
  description = "Vault address."
  type        = string
}

variable "vault_token" {
  # 한국어 주석: KV secret을 쓸 수 있는 Vault token입니다.
  description = "Vault token."
  type        = string
  sensitive   = true
}

variable "vault_skip_tls_verify" {
  # 한국어 주석: 내부 CA를 신뢰하지 않는 로컬 환경에서만 true로 둡니다.
  description = "Skip Vault TLS verification."
  type        = bool
  default     = true
}

variable "vault_kv_mount" {
  # 한국어 주석: README의 secret/apps/example에서 secret에 해당하는 KV v2 mount 이름입니다.
  description = "Vault KV v2 mount name."
  type        = string
  default     = "secret"
}

variable "harbor_host" {
  # 한국어 주석: Kubernetes imagePullSecret의 auths key와 image 주소에 사용할 hostname입니다.
  description = "Harbor registry hostname without scheme."
  type        = string
  default     = "harbor.onprem.arpa"
}

variable "precreated_robot_account_name" {
  # 한국어 주석: 미리 만든 Harbor robot account의 전체 이름입니다. 모든 앱의 GitHub Actions와 Kubernetes imagePullSecret에서 공용으로 사용합니다.
  description = "Pre-created Harbor robot account name for image push/pull."
  type        = string
}

variable "precreated_robot_account_secret" {
  # 한국어 주석: precreated_robot_account_name의 secret입니다. Terraform이 생성하지 않고 Vault Harbor pull credential에 저장만 합니다.
  description = "Pre-created Harbor robot account secret."
  type        = string
  sensitive   = true
}

variable "apps" {
  # 한국어 주석: 앱별 Harbor project, repository, Vault secret 경로와 값을 정의합니다.
  description = "On-prem app resource definitions keyed by logical app name."
  type = map(object({
    harbor_project         = string
    harbor_project_public  = optional(bool, false)
    harbor_force_destroy   = optional(bool, false)
    vulnerability_scanning = optional(bool, true)
    auto_sbom_generation   = optional(bool, false)

    # 한국어 주석: 기존 단일 repository/secret 입력과의 호환용 필드입니다. 새 앱은 아래 map 필드를 권장합니다.
    harbor_repository        = optional(string)
    vault_harbor_secret_path = optional(string)
    vault_app_secret_path    = optional(string)
    app_secret_values        = optional(map(string), {})

    harbor_repositories = optional(map(object({
      name = string
    })), {})

    harbor_pull_secrets = optional(map(object({
      path = string
    })), {})

    app_secrets = optional(map(object({
      path   = string
      values = optional(map(string), {})
    })), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for app in values(var.apps) : app.harbor_repository != null || length(app.harbor_repositories) > 0
    ])
    error_message = "Each app must define harbor_repository or at least one item in harbor_repositories."
  }
}
