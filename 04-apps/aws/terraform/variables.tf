variable "aws_region" {
  # 한국어 주석: 앱 ECR repository와 Secrets Manager secret을 만들 AWS region입니다.
  description = "AWS region where app resources will be created."
  type        = string
  default     = "ap-northeast-2"
}

variable "default_tags" {
  # 한국어 주석: 앱별 AWS 리소스에 적용할 공통 태그입니다.
  description = "Default tags applied to app AWS resources."
  type        = map(string)
  default = {
    Project = "My-IaC-GitOps"
  }
}

variable "create_github_oidc_provider" {
  # 한국어 주석: AWS 계정에 GitHub Actions OIDC provider가 아직 없을 때만 true로 둡니다.
  description = "Create the GitHub Actions OIDC provider in this AWS account."
  type        = bool
  default     = false
}

variable "github_oidc_thumbprints" {
  # 한국어 주석: create_github_oidc_provider=true일 때 사용합니다. GitHub Actions OIDC TLS thumbprint입니다.
  description = "Thumbprints for token.actions.githubusercontent.com when creating the GitHub OIDC provider."
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "apps" {
  # 한국어 주석: 앱별 ECR, GitHub Actions push role, Secrets Manager secret 구성을 한 곳에서 정의합니다.
  description = "App AWS resource definitions keyed by logical app name."
  type = map(object({
    github_owner       = string
    github_repo        = string
    github_branch      = optional(string, "main")
    ecr_push_role_name = string

    ecr_repositories = optional(map(object({
      name                   = string
      force_delete           = optional(bool, false)
      image_tag_mutability   = optional(string, "MUTABLE")
      scan_on_push           = optional(bool, true)
      extra_ecr_push_actions = optional(list(string), [])
    })), {})

    secrets = optional(map(object({
      name            = string
      values          = optional(map(string), {})
      recovery_window = optional(number, 7)
    })), {})
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for app in values(var.apps) : [
        for repo in values(app.ecr_repositories) : contains(["MUTABLE", "IMMUTABLE"], repo.image_tag_mutability)
      ]
    ]))
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }

  validation {
    condition = alltrue([
      for app in values(var.apps) : length(app.ecr_repositories) > 0
    ])
    error_message = "Each app must define at least one item in ecr_repositories."
  }
}
