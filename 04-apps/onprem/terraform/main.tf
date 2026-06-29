locals {
  harbor_projects = {
    for project_name in distinct([for app in values(var.apps) : app.harbor_project]) : project_name => {
      harbor_project_public  = one(distinct([for app in values(var.apps) : app.harbor_project_public if app.harbor_project == project_name]))
      harbor_force_destroy   = one(distinct([for app in values(var.apps) : app.harbor_force_destroy if app.harbor_project == project_name]))
      vulnerability_scanning = one(distinct([for app in values(var.apps) : app.vulnerability_scanning if app.harbor_project == project_name]))
      auto_sbom_generation   = one(distinct([for app in values(var.apps) : app.auto_sbom_generation if app.harbor_project == project_name]))
    }
  }

  app_harbor_repository_maps = [
    for app_key, app in var.apps : merge(
      app.harbor_repository == null ? {} : {
        "${app_key}/default" = {
          app_key  = app_key
          repo_key = "default"
          name     = app.harbor_repository
        }
      },
      {
        for repo_key, repo in app.harbor_repositories : "${app_key}/${repo_key}" => {
          app_key  = app_key
          repo_key = repo_key
          name     = repo.name
        }
      }
    )
  ]

  harbor_repositories = length(local.app_harbor_repository_maps) > 0 ? merge(local.app_harbor_repository_maps...) : {}

  app_harbor_pull_secret_maps = [
    for app_key, app in var.apps : merge(
      app.vault_harbor_secret_path == null ? {} : {
        "${app_key}/default" = {
          app_key    = app_key
          secret_key = "default"
          path       = app.vault_harbor_secret_path
        }
      },
      {
        for secret_key, secret in app.harbor_pull_secrets : "${app_key}/${secret_key}" => {
          app_key    = app_key
          secret_key = secret_key
          path       = secret.path
        }
      }
    )
  ]

  harbor_pull_secrets = length(local.app_harbor_pull_secret_maps) > 0 ? merge(local.app_harbor_pull_secret_maps...) : {}
  harbor_pull_secret_paths = toset([
    for secret in values(local.harbor_pull_secrets) : secret.path
  ])

  app_secret_maps = [
    for app_key, app in var.apps : merge(
      app.vault_app_secret_path == null ? {} : {
        "${app_key}/default" = {
          app_key    = app_key
          secret_key = "default"
          path       = app.vault_app_secret_path
          values     = app.app_secret_values
        }
      },
      {
        for secret_key, secret in app.app_secrets : "${app_key}/${secret_key}" => {
          app_key    = app_key
          secret_key = secret_key
          path       = secret.path
          values     = secret.values
        }
      }
    )
  ]

  app_secrets = length(local.app_secret_maps) > 0 ? merge(local.app_secret_maps...) : {}
}

resource "harbor_project" "app" {
  for_each = local.harbor_projects

  # 한국어 주석: 앱 이미지를 보관할 Harbor project입니다. 이미지 push/pull 권한은 미리 만든 robot account로 관리합니다.
  name                   = each.key
  public                 = each.value.harbor_project_public
  force_destroy          = each.value.harbor_force_destroy
  vulnerability_scanning = each.value.vulnerability_scanning
  auto_sbom_generation   = each.value.auto_sbom_generation
}

resource "vault_kv_secret_v2" "harbor_pull" {
  for_each = local.harbor_pull_secret_paths

  # 한국어 주석: ExternalSecret이 imagePullSecret을 만들 때 읽는 미리 만든 Harbor robot credential입니다.
  mount = var.vault_kv_mount
  name  = each.value
  data_json = jsonencode({
    username = var.precreated_robot_account_name
    password = var.precreated_robot_account_secret
  })
}

resource "vault_kv_secret_v2" "app" {
  for_each = {
    for key, secret in local.app_secrets : key => secret
    if length(secret.values) > 0
  }

  # 한국어 주석: ExternalSecret이 앱 환경변수 secret을 만들 때 읽는 런타임 secret입니다.
  mount     = var.vault_kv_mount
  name      = each.value.path
  data_json = jsonencode(each.value.values)
}
