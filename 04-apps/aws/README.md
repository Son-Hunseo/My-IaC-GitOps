# Apps - AWS

앱별 AWS 리소스를 생성하는 Terraform 실행 단위입니다.

생성 대상:

1. ECR repositories
2. 앱별 GitHub Actions ECR push IAM role
3. Secrets Manager secrets와 secret versions
4. 선택적으로 GitHub Actions OIDC provider

## 사용법

```bash
cd 04-apps/aws/terraform
cp terraform.tfvars.example terraform.tfvars
```

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

`terraform.tfvars`는 `.gitignore` 대상입니다. 실제 secret 값은 `terraform.tfvars.example`에 넣지 마십시오.

앱 하나에 ECR repository와 Secrets Manager secret을 여러 개 둘 수 있습니다.

```hcl
apps = {
  example = {
    github_owner       = "sonhunseo"
    github_repo        = "example"
    github_branch      = "main"
    ecr_push_role_name = "github-actions-ecr-push-example"

    ecr_repositories = {
      api = {
        name = "example-api"
      }
      worker = {
        name = "example-worker"
      }
    }

    secrets = {
      app = {
        name = "apps/example/app"
        values = {
          DATABASE_URL   = "postgres://user:password@postgres.example.svc:5432/example"
          SESSION_SECRET = "replace-me"
        }
      }
      oauth = {
        name = "apps/example/oauth"
        values = {
          OAUTH_CLIENT_ID     = "replace-me"
          OAUTH_CLIENT_SECRET = "replace-me"
        }
      }
    }
  }
}
```

## terraform.tfvars 항목 설명

`terraform.tfvars`에는 앱별 ECR repository, GitHub Actions IAM role, Secrets Manager secret 구성을 넣습니다.

### 공통 설정

`aws_region`에는 앱 리소스를 만들 AWS region을 넣습니다. 서울 region을 사용하면 아래 값을 그대로 둡니다.

```hcl
aws_region = "ap-northeast-2"
```

`default_tags`에는 생성되는 AWS 리소스에 공통으로 붙일 태그를 넣습니다. 비용 추적, 리소스 검색, 운영 환경 구분에 사용합니다.

```hcl
default_tags = {
  Project     = "My-GitAIOps"
  Layer       = "apps"
}
```

`create_github_oidc_provider`는 AWS 계정에 GitHub Actions OIDC provider를 만들지 여부입니다. 같은 AWS 계정에 `token.actions.githubusercontent.com` provider가 이미 있으면 `false`, 아직 없으면 `true`로 둡니다.

```hcl
create_github_oidc_provider = true
```

`github_oidc_thumbprints`는 `create_github_oidc_provider = true`일 때만 사용합니다. 기본값이 있으므로 특별한 이유가 없으면 따로 수정하지 않아도 됩니다.

```hcl
github_oidc_thumbprints = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
```

### apps

`apps`는 앱별 설정 map입니다. `example`, `my_blog`, `chocoletter` 같은 key는 Terraform 내부에서 앱을 구분하는 논리 이름입니다.

```hcl
apps = {
  my_blog = {
    # 앱 설정
  }
}
```

앱별 필수 항목은 아래와 같습니다.

`github_owner`에는 GitHub repository 소유자를 넣습니다. 개인 repository면 사용자명, 조직 repository면 조직명을 넣습니다.

```hcl
github_owner = "sonhunseo"
```

`github_repo`에는 GitHub repository 이름을 넣습니다.

```hcl
github_repo = "my-blog"
```

`github_branch`에는 ECR push workflow가 실행될 branch 이름을 넣습니다. 생략하면 `"main"`입니다. 이 값은 IAM role trust policy에 들어가므로, 여기에 적은 branch의 GitHub Actions만 ECR push role을 사용할 수 있습니다.

```hcl
github_branch = "main"
```

`ecr_push_role_name`에는 GitHub Actions가 ECR에 이미지를 push할 때 사용할 IAM role 이름을 넣습니다. 앱마다 고유한 이름을 사용합니다.

```hcl
ecr_push_role_name = "github-actions-ecr-push-my-blog"
```

### ecr_repositories

`ecr_repositories`에는 앱 이미지가 저장될 ECR repository 목록을 넣습니다. `api`, `worker`, `client`, `server` 같은 key는 Terraform 내부 구분용이고, 실제 ECR repository 이름은 `name`입니다.

```hcl
ecr_repositories = {
  api = {
    name = "my-blog-api"
  }
  worker = {
    name = "my-blog-worker"
  }
}
```

### secrets

`secrets`에는 AWS Secrets Manager에 만들 앱 secret 목록을 넣습니다. `app`, `oauth`, `database` 같은 key는 Terraform 내부 구분용이고, 실제 Secrets Manager 이름은 `name`입니다.

```hcl
secrets = {
  app = {
    name = "apps/my-blog/app"
    values = {
      DATABASE_URL   = "postgres://user:password@postgres.example.svc:5432/my_blog"
      SESSION_SECRET = "replace-me"
    }
  }
}
```

`name`에는 Secrets Manager secret 이름을 넣습니다. EKS External Secrets Operator 권한을 단순하게 관리하려면 `apps/<app-name>/<secret-name>` 패턴을 권장합니다.

```hcl
name = "apps/my-blog/app"
```

`values`에는 secret에 JSON으로 저장될 key-value 값을 넣습니다. 앱에서 환경변수로 사용할 DB URL, session secret, OAuth client secret, API token 등을 넣습니다.

```hcl
values = {
  DATABASE_URL        = "postgres://user:password@postgres.example.svc:5432/my_blog"
  SESSION_SECRET      = "replace-with-real-random-value"
  OAUTH_CLIENT_ID     = "replace-me"
  OAUTH_CLIENT_SECRET = "replace-me"
}
```

실제 비밀번호, token, OAuth secret, DB URL은 ignore되는 `terraform.tfvars`에만 넣고, `terraform.tfvars.example`이나 git에 commit되는 파일에는 넣지 마십시오. Secrets Manager secret value는 Terraform state에도 저장됩니다.

## State 관리

초기 구성은 로컬 state를 사용합니다. `terraform.tfvars`, `*.tfstate`, `*.tfstate.*`, `.terraform/`는 repository `.gitignore`에 포함되어 있습니다.

Secrets Manager에 넣는 `secrets`의 `values`는 Terraform state에도 저장됩니다. 현재는 로컬 state를 git에 올리지 않는 전제로 사용하고, 협업이나 운영 환경이 필요해지면 S3 backend와 state 접근 제어를 추가합니다.

## EKS External Secrets 권한

이 Terraform은 Secrets Manager secret을 만들지만, EKS의 External Secrets Operator 읽기 권한까지 자동으로 수정하지는 않습니다.

Kubernetes `ExternalSecret`이 이 secret을 읽으려면 `01-infra/aws/terraform/terraform.tfvars`의 `external_secrets_secret_arns`에 secret ARN이 포함돼야 합니다. 앱 secret 이름을 `apps/...` 패턴으로 만들면 아래처럼 `apps/*` 범위를 추가합니다.

```hcl
external_secrets_secret_arns = [
  "arn:aws:secretsmanager:ap-northeast-2:<account-id>:secret:apps/*"
]
```

그 뒤 `01-infra/aws/terraform`에서 `terraform plan`과 `terraform apply`를 실행해 External Secrets Operator IAM policy를 갱신합니다.

## GitHub Actions 설정

`terraform output apps`에서 앱별 `ecr_push_role_arn`, `ecr_repositories`, `secrets`를 확인한 뒤 workflow와 manifest에 넣습니다.
