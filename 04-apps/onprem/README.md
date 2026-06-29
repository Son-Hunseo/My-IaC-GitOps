# Apps - On-Premise

앱별 On-Premise 외부 리소스를 생성하는 Terraform 실행 단위입니다.

이 영역은 앱 자체의 GitOps manifest를 관리하는 곳이 아닙니다. 각 앱의 GitOps 구성은 앱별로 별도 repository에서 각각 관리하고, 이 영역에서는 해당 앱들이 실행되기 위해 필요한 On-Premise 내부 시스템 리소스만 준비합니다.

현재 구성은 컨테이너 레지스트리(Harbor)와 시크릿 저장소(Vault)만 필요한 앱을 기준으로 합니다. 앱이 데이터베이스, 캐시, 메시지 큐, 오브젝트 스토리지, SSO, 관측 시스템 등 추가 내부 시스템을 필요로 하게 되면, 해당 앱에 필요한 리소스만 이 영역에 추가할 수 있습니다.

Terraform 1.11 이상이 필요합니다.

생성 대상:

1. Harbor project
2. Vault KV v2 Harbor pull credentials
3. Vault KV v2 앱 런타임 secrets

Harbor repository는 별도 생성 리소스가 아니라 이미지 push 시 `project/repository` 경로로 만들어집니다.

Harbor robot account는 이 Terraform에서 생성하지 않습니다.

## 사전 준비

먼저 사용할 Robot 계정을 생성합니다.

해당 Robot 계정은 모든 프로젝트를 커버하며(모든 프로젝트에 대한 권한), 다음과 같은 권한이 필요합니다.

1. `Pull Repository` - Pod를 만들 때, Image Pull 용도 (External Secret에서 Robot 계정을 Pod의 imagePullSecrets로 주입)
2. `Push Repository` - Github Action에서 빌드 후 Push 용도 (Github Action Secret으로 Robot 계정 등록)
3. `List Artifact` - Github Action에서 현재 마지막 이미지 버전을 확인하는 용도 (Github Action Secret으로 Robot 계정 등록)

```bash
cd 04-apps/onprem/terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`에 값들을 프로젝트에 맞게 수정합니다.

`harbor_username`, `harbor_password`에는 Project를 생서하기 위해 Harbor 관리자 계정을 넣습니다.

`precreated_robot_account_name`, `precreated_robot_account_secret`에는 Robot account의 전체 이름(`robot$<id>`)과 secret을 넣습니다. (이 값들이 Vault의 시크릿으로 저장된다)

`vault_token`에는 `vault_kv_mount` 아래에 Harbor pull credential과 앱 런타임 secret을 쓸 수 있는 token 값을 넣습니다.

`terraform.tfvars`의 `apps.*.harbor_project`는 Terraform이 생성할 Harbor project 이름입니다.

`apps.*.app_secrets`에 필요한 시크릿들을 작성합니다.

앱 하나에 Harbor repository 경로와 Vault secret을 여러 개 둘 수 있습니다.

```hcl
precreated_robot_account_name   = "robot$shared"
precreated_robot_account_secret = "replace-me-precreated-robot-token"

apps = {
  example = {
    harbor_project = "son"

    harbor_repositories = {
      api = {
        name = "example-api"
      }
      worker = {
        name = "example-worker"
      }
    }

    harbor_pull_secrets = {
      default = {
        path = "platform/harbor/example"
      }
    }

    app_secrets = {
      app = {
        path = "apps/example/app"
        values = {
          DATABASE_URL   = "postgres://user:password@postgres.example.svc:5432/example"
          SESSION_SECRET = "replace-me"
        }
      }
      oauth = {
        path = "apps/example/oauth"
        values = {
          OAUTH_CLIENT_ID     = "replace-me"
          OAUTH_CLIENT_SECRET = "replace-me"
        }
      }
    }
  }
}
```

## 실행

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

## State 관리

초기 구성은 로컬 state를 사용합니다. `terraform.tfvars`, `*.tfstate`, `*.tfstate.*`, `.terraform/`는 repository `.gitignore`에 포함되어 있습니다.

Vault에 넣는 `app_secrets`와 Harbor pull credential은 Terraform state에도 저장됩니다. 현재는 로컬 state를 git에 올리지 않는 전제로 사용하고, 협업이나 운영 환경이 필요해지면 remote backend와 state 접근 제어를 추가합니다.

## Vault Path

`vault_kv_mount = "secret"`이면 `harbor_pull_secrets.default.path = "platform/harbor/example"`는 Vault CLI 기준 `secret/platform/harbor/example`에 저장됩니다.

External Secrets Operator의 `remoteRef.key`에는 mount를 제외한 값을 씁니다.

```yaml
remoteRef:
  key: platform/harbor/example
```

## GitHub Actions 설정

GitHub Actions에는 미리 만든 Harbor robot account를 사용합니다. username은 `precreated_robot_account_name`, password는 `precreated_robot_account_secret` 값입니다.
