data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints
}

locals {
  github_actions_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.github_actions[0].arn
  ecr_push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:CompleteLayerUpload",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]

  app_ecr_repository_maps = [
    for app_key, app in var.apps : {
      for repo_key, repo in app.ecr_repositories : "${app_key}/${repo_key}" => {
        app_key                = app_key
        repo_key               = repo_key
        name                   = repo.name
        force_delete           = repo.force_delete
        image_tag_mutability   = repo.image_tag_mutability
        scan_on_push           = repo.scan_on_push
        extra_ecr_push_actions = repo.extra_ecr_push_actions
      }
    }
  ]

  ecr_repositories = length(local.app_ecr_repository_maps) > 0 ? merge(local.app_ecr_repository_maps...) : {}

  app_secret_maps = [
    for app_key, app in var.apps : {
      for secret_key, secret in app.secrets : "${app_key}/${secret_key}" => {
        app_key         = app_key
        secret_key      = secret_key
        name            = secret.name
        values          = secret.values
        recovery_window = secret.recovery_window
      }
    }
  ]

  secrets = length(local.app_secret_maps) > 0 ? merge(local.app_secret_maps...) : {}
}

resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repositories

  # 한국어 주석: 앱 이미지를 저장할 ECR repository입니다.
  name                 = each.value.name
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.secrets

  # 한국어 주석: External Secrets Operator가 읽을 앱 런타임 secret입니다.
  name                    = each.value.name
  recovery_window_in_days = each.value.recovery_window
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = {
    for key, secret in local.secrets : key => secret
    if length(secret.values) > 0
  }

  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode(each.value.values)
}

data "aws_iam_policy_document" "ecr_push_assume_role" {
  for_each = var.apps

  # 한국어 주석: 지정한 GitHub repository와 branch의 workflow만 앱별 push role을 수임할 수 있습니다.
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_actions_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${each.value.github_owner}/${each.value.github_repo}:ref:refs/heads/${each.value.github_branch}"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  for_each = var.apps

  name               = each.value.ecr_push_role_name
  assume_role_policy = data.aws_iam_policy_document.ecr_push_assume_role[each.key].json
}

data "aws_iam_policy_document" "ecr_push" {
  for_each = var.apps

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushImage"
    effect = "Allow"
    actions = distinct(concat(
      local.ecr_push_actions,
      flatten([
        for key, repo in local.ecr_repositories : repo.extra_ecr_push_actions
        if repo.app_key == each.key
      ])
    ))
    resources = [
      for key, repo in aws_ecr_repository.app : repo.arn
      if local.ecr_repositories[key].app_key == each.key
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = var.apps

  name   = "${each.value.ecr_push_role_name}-policy"
  role   = aws_iam_role.ecr_push[each.key].id
  policy = data.aws_iam_policy_document.ecr_push[each.key].json
}
