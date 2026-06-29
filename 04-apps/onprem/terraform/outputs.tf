output "apps" {
  # 한국어 주석: GitHub Actions, Kustomize image, ExternalSecret 작성에 필요한 값을 출력합니다.
  description = "On-prem app resource outputs."
  value = {
    for name, app in var.apps : name => {
      harbor_project     = harbor_project.app[app.harbor_project].name
      robot_account_name = var.precreated_robot_account_name
      harbor_repositories = {
        for key, repo in local.harbor_repositories : repo.repo_key => {
          repository_name = repo.name
          image           = "${var.harbor_host}/${harbor_project.app[app.harbor_project].name}/${repo.name}:<tag>"
        }
        if repo.app_key == name
      }
      harbor_pull_secrets = {
        for key, secret in local.harbor_pull_secrets : secret.secret_key => {
          vault_remote_key = secret.path
        }
        if secret.app_key == name
      }
      app_secrets = {
        for key, secret in local.app_secrets : secret.secret_key => {
          vault_remote_key = secret.path
        }
        if secret.app_key == name
      }
    }
  }
}
