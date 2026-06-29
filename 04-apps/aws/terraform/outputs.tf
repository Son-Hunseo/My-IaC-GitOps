output "apps" {
  # 한국어 주석: GitHub Actions와 Kubernetes manifest에서 사용할 앱별 주요 값을 출력합니다.
  description = "App AWS resource outputs."
  value = {
    for name, app in var.apps : name => {
      ecr_push_role_arn = aws_iam_role.ecr_push[name].arn
      ecr_repositories = {
        for key, repo in aws_ecr_repository.app : local.ecr_repositories[key].repo_key => {
          repository_url    = repo.repository_url
          repository_arn    = repo.arn
          image_uri_example = "${repo.repository_url}:<tag>"
        }
        if local.ecr_repositories[key].app_key == name
      }
      secrets = {
        for key, secret in aws_secretsmanager_secret.app : local.secrets[key].secret_key => {
          name = secret.name
          arn  = secret.arn
        }
        if local.secrets[key].app_key == name
      }
    }
  }
}

output "github_actions_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN used by the app push roles."
  value       = local.github_actions_oidc_provider_arn
}
