# On-Premise Platform GitOps

이 디렉터리는 이미 부트스트랩이 끝난 On-Premise Kubernetes 클러스터의 플랫폼 구성요소를 Argo CD로 설치합니다.
Argo CD 자체 설치는 `02-bootstrap/onprem` 단계의 책임이며, 여기서는 Argo CD가 동기화할 클러스터 애드온과 운영 컴포넌트만 다룹니다.

중요: `kubectl apply -f 03-k8s-clusters/onprem`로 한 번에 설치하지 않습니다.
`argocd/projects/platform.yaml`과 root `Application`을 적용하고, root `Application`이 하위 platform component들을 동기화하게 만듭니다.

## 구성

- `argocd/projects/platform.yaml`: Argo CD `AppProject`입니다.
- `argocd/applications/platform.yaml`: On-Premise root `Application`입니다.
- `overlays/`: On-Premise 클러스터 전용 Kubernetes 리소스와 child `Application`입니다.
- `values/`: Helm chart에 전달할 On-Premise values 파일입니다.

## 사전 조건

Argo CD가 먼저 설치되어 있어야 합니다.

```bash
kubectl get namespace argocd
kubectl -n argocd get pods
```

## 사전 설정

MetalLB address pool을 실제 노드 네트워크에서 사용 가능한 IP 대역으로 바꿉니다.

```text
03-k8s-clusters/onprem/overlays/metallb/metallb-address-pool.yaml
```

다음 파일을 수정하여 실제 NAS GUI 대시보드 경로로 바꿔줍니다.

```text
03-k8s-clusters/onprem/overlays/nas/service.yaml
```

On-Premise overlay는 NAS NFS export를 사용하는 NFS Subdir External Provisioner를 설치하고 `nas-sc`를 기본 `StorageClass`로 설정합니다.

기본 NAS NFS 설정은 다음 파일에서 관리합니다.

```text
03-k8s-clusters/onprem/values/nfs-subdir-external-provisioner-values.yaml
```

예시는 다음과 같습니다.

```yaml
nfs:
  server: <NAS-IP>
  path: /volume1/k8s-sc

storageClass:
  name: nas-sc
  defaultClass: true
```

PVC를 사용하는 주요 values 파일을 확인하고 필요한 값들을 바꿉니다.
Harbor - `externalURL`, `storageClass`
Prometheus, Grafana, Vault - `storageClass`

```text
03-k8s-clusters/onprem/values/vault-values.yaml
03-k8s-clusters/onprem/values/prometheus-values.yaml
03-k8s-clusters/onprem/values/grafana-values.yaml
03-k8s-clusters/onprem/values/harbor-values.yaml
```


## Gateway와 인증서

Internal Gateway는 내부 플랫폼 UI를 `*.onprem.arpa` wildcard 인증서로 HTTPS 노출합니다.

Argo CD, Harbor, Vault, Prometheus, Grafana의 `HTTPRoute`는 Gateway의 `https` listener에 연결됩니다.

인증서는 cert-manager가 자체 서명 root CA와 내부 wildcard leaf 인증서를 생성하는 방식입니다.

아래 파일들은 위에 설명한 부분 관련 파일입니다.

```text
03-k8s-clusters/onprem/overlays/internal-gateway/internal-ca.yaml
03-k8s-clusters/onprem/overlays/internal-gateway/gateway.yaml
03-k8s-clusters/onprem/overlays/internal-gateway/routes-*.yaml
```

External Gateway는 `sonhs.com`, `*.sonhs.com` Gateway listener와 Let’s Encrypt `ClusterIssuer`를 포함합니다.

wildcard 인증서는 ACME HTTP-01로 발급할 수 없으므로 Route53 DNS-01 solver를 사용합니다.

수정 대상은 다음 파일입니다.

```text
03-k8s-clusters/onprem/overlays/cluster-issuer/letsencrypt-prod.yaml
```

`REPLACE_ROUTE53_HOSTED_ZONE_ID`를 Route53 Hosted Zone ID로 바꿉니다.

```yaml
hostedZoneID: Z0123456789EXAMPLE
```

위 설정이 적용되서 인증서가 발급되려면, Cluster Issuer에서 Route53에 접근이 가능해야하고, 이를 위해서는 관련 권한이 있는 IAM의 엑세스 키와 엑세스 시크릿 키가 필요합니다.

좀 전에 수정 한 `letsencrypt-prod.yaml`을 보면 `route53-credentials-secret`이라는 Secret에서 값을 가져옵니다.

하지만 이 Secret을 직접 생성하지 않습니다. (GitOps로 넣기에 부적절한 값이므로)

Vault에 External Secert을 연결하여 값을 주입 받습니다.
(관련 설정: `03-k8s-clusters/onprem/overlays/cluster-issuer/route53-credentials.externalsecret.yaml`)

On-Premise overlay는 External Secrets Operator가 Vault에서 값을 읽어 `cert-manager/route53-credentials-secret`을 생성합니다.

> 위 과정은 아래 과정 중 Vault를 초기화 -> Vault에 시크릿 생성 과정이 완료된 이후에 회복되는 과정으로 완료됩니다.

추가적으로 Route53 DNS 설정에서 외부 도메인으로 사용할 `sonhs.com`과 `*.sonhs.com`은 나의 온프레미스 서버의 외부 공인 IP로 보내야합니다.

내 온프레미스 서버의 게이트웨이(예: 공유기)에서 내 클러스터 External Gateway로 포트포워딩 해줍니다.

## GitHub Actions Runner

GitHub Actions self-hosted runner는 On-Premise overlay에만 포함됩니다.
ARC는 GitHub 공식 `gha-runner-scale-set-controller`, `gha-runner-scale-set` Helm chart를 사용하며, chart version은 두 Application 모두 `0.14.2`로 고정되어 있습니다.

수정 대상은 다음 파일입니다.

```text
03-k8s-clusters/onprem/values/github-runner-scale-set-values.yaml
```

우리의 Runner가 GitHub에 붙기 위해서는 인증이 필요합니다. 

이에 우리가 원하는 레포에 필요한 권한을 가진 PAT이 필요합니다.

PAT 권한 예시는 다음과 같습니다.

- repository runner: fine-grained PAT는 대상 repository의 `Administration: Read and write`, classic PAT는 `repo`

이 값 또한 직접 넣는 것이 아니라, 위의 Route53 접근 방식 처럼 Vault에 등록한 PAT을 주입받습니다.

Vault에서 인증값을 읽는 경로는 `runnerAuth.vaultSecretPath`로 결정합니다.

```yaml
runnerAuth:
  ..
  vaultSecretPath: platform/github-actions-runner
  ..
```

다음으로, 아래처럼 runner를 정의할 수 있습니다. (Github Action 스크립트에서 `runs-on: `에 value로 들어갈 값은 `runnerScaleSetName`이다)

```yaml
runnerScaleSets:
  - name: my-runner1
    runnerScaleSetName: my-project1-runner
    githubConfigUrl: https://github.com/Son-Hunseo/my-gitaiops
    minRunners: 0
    maxRunners: 3
  - name: my-runner2
    runnerScaleSetName: my-project2-runner
    githubConfigUrl: https://github.com/Son-Hunseo/my-gitaiops2
    minRunners: 0
    maxRunners: 3
```

GitHub Actions workflow에서는 다음처럼 사용합니다.

```yaml
runs-on: my-project1-runner
```

## Root Application 적용

프로젝트 루트에서 실행합니다.

```bash
kubectl apply -f 03-k8s-clusters/onprem/argocd/projects/platform.yaml
kubectl apply -f 03-k8s-clusters/onprem/argocd/applications/platform.yaml
```

## 내부 DNS 설정

> 아래 과정은 온프레미스 내부망(클러스터 외부이지만, 온프레미스 내부망)에 내부 DNS 서버(글로벌 DNS를 업스트림으로 하는)를 따로 운영하고 있다고 가정한다.

> 만약 내부 DNS 서버를 사용하지 않는다면, 컨테이너 레지스트리의 도메인을 각 워커노드의 `/etc/hosts`에 등록하고, `CoreDNS`에 직접 등록하면 된다.

Pod를 생성 시 컨테이너 이미지를 Pull하는 과정은 다음과 같다.

1. Scheduler가 Pod를 배치할 Node를 선택
2. 선택받은 Node의 Kubelet이 컨테이너 런타임(containerd)에 image pull 요청
3. 컨테이너 런타임은 Node의 DNS 설정으로 컨테이너 레지스트리 도메인을 해석

이에 각 노드가 바라보고 있는 내부 DNS 서버에 컨테이너 레지스트리의 도메인을 등록한다. (아래 코드 블럭에서는 그냥 harbor 등록하는 김에 다른 것도 등록하려고 내부 컴포넌트의 도메인을 다 등록한 것)

```text
harbor.onprem.arpa  -> <internal-gateway-ip>
argocd.onprem.arpa  -> <internal-gateway-ip>
vault.onprem.arpa   -> <internal-gateway-ip>
grafana.onprem.arpa -> <internal-gateway-ip>
```

> 트러블슈팅 : 혹시나 간헐적으로 ImagePullBackOff 가 뜬다면, `/etc/netplan/50-cloud-init.yaml` 을 확인하고 `nameserver` 항목에 내부 DNS외에 다른게 있다면, 지우고 `sudo netplan apply` 입력한다.

우리는 CI 과정에서 Github Action Self-Hosted Runner를 사용한다.

이때, 아마 CI 스크립트 과정 중 컨테이너 레지스트리에 push하는 스크립트가 있을텐데, Pod는 노드에 설정된 DNS 설정을 따르는 것이 아니라, `CoreDNS`를 DNS 서버로 따른다.

이에, GitHub Actions runner가 내부 컨테이너 레지스트리의 도메인을 조회할 수 있도록 `CoreDNS`에는 `onprem.arpa` zone을 내부 DNS 서버로 forwarding하는 업스트림을 추가한다.

```bash
kubectl -n kube-system edit configmap coredns
```

아래처럼 `kubernetes` 플러그인 뒤에 `onprem.arpa` 전용 `forward`를 추가합니다.

```text
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready

    kubernetes cluster.local in-addr.arpa
    ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    forward onprem.arpa <internal-dns-server-ip>
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

이후 `CoreDNS`를 재시작 합니다.

```bash
kubectl -n kube-system rollout restart deployment/coredns
```

## 인증서 신뢰 설정

내부 root CA를 추출합니다.

```bash
kubectl -n nginx-gateway get secret onprem-root-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > onprem-root-ca.crt
```

worker node containerd가 `*.onprem.arpa` HTTPS 인증서를 신뢰하도록 이 CA를 등록합니다.

worker node에 아래 명령어를 반복해서 containerd가 내부 인증서를 신뢰하도록 합니다.(각 worker node 반복)

```bash
ssh <user>@<worker1> "sudo mkdir /etc/containerd/certs.d"
ssh <user>@<worker1> "sudo mkdir /etc/containerd/certs.d/harbor.onprem.arpa"

scp onprem-root-ca.crt <user>@<worker1>:~

ssh <user>@<worker1> "sudo mv ~/onprem-root-ca.crt /etc/containerd/certs.d/harbor.onprem.arpa/ca.crt"
```

```bash
ssh <user>@<worker1>
```

```bash
sudo nano /etc/containerd/certs.d/harbor.onprem.arpa/hosts.toml
```

containerd의 Harbor trust 예시는 다음과 같습니다.

```toml
server = "https://harbor.onprem.arpa"

[host."https://harbor.onprem.arpa"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.onprem.arpa/ca.crt"
```

```bash
sudo systemctl restart containerd
```

추가적으로 Github Runner가 Harbor에 접속하기 위해서는 내부 인증서를 신뢰해야합니다. (Harbor ExternalURL이 https이며 이를 내부 인증서로 인증하고 있으므로)

Runner의 DinD Docker daemon은 `harbor-registry-ca` Secret을 `/etc/docker/certs.d/harbor.onprem.arpa`에 마운트하도록 GitOps values에 정의되어 있습니다.
root CA 추출 후 `arc-runners` 네임스페이스에 같은 이름의 Secret을 만듭니다.

```bash
kubectl -n arc-runners create secret generic harbor-registry-ca \
  --from-file=ca.crt=onprem-root-ca.crt \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Vault 초기화

Vault는 Helm chart가 설치되어 Pod가 떠도 바로 사용할 수 있는 상태가 아닙니다.
처음 기동 후에는 운영자가 별도로 `init`, `unseal`, KV engine, Kubernetes auth method 설정을 수행해야 합니다.

이 단계가 끝나기 전까지 `ClusterSecretStore`와 Vault 기반 `ExternalSecret`은 정상화되지 않습니다.

Vault Pod와 Service가 생성되었는지 확인합니다.

```bash
kubectl -n vault get pod,svc,endpoints
kubectl -n vault exec onprem-vault-0 -- vault status
```

처음 상태는 보통 다음처럼 보입니다.

```text
Initialized    false
Sealed         true
```

Vault를 초기화합니다.
운영 환경에서는 key share와 threshold를 조직의 복구 정책에 맞춥니다.
테스트 환경에서만 단순화를 위해 `1/1`을 사용할 수 있습니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault operator init -key-shares=1 -key-threshold=1
```

출력되는 `Unseal Key`와 `Initial Root Token`은 다시 조회할 수 없습니다.
Git, values 파일, ConfigMap에 저장하지 말고 안전한 secret 보관소에 저장합니다.

Vault를 unseal하고 root token으로 로그인합니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault operator unseal <unseal-key>
kubectl -n vault exec onprem-vault-0 -- vault login <root-token>
```

먼저 Vault가 Kubernetes TokenReview API를 호출할 수 있도록 RBAC를 준비합니다.

Vault 서버 ServiceAccount 이름은 현재 Helm release 기준으로 `onprem-vault`입니다.

```bash
kubectl create clusterrolebinding vault-token-reviewer \
  --clusterrole=system:auth-delegator \
  --serviceaccount=vault:onprem-vault \
  --dry-run=client -o yaml | kubectl apply -f -
```

`ClusterSecretStore`는 `path: secret`, `version: v2`를 사용하므로 `secret/` 경로에 KV v2 engine이 필요합니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault secrets enable -path=secret kv-v2
```

`path is already in use` 또는 이미 활성화되어 있다는 에러가 나오면 그 에러는 무시하고, 바로 아래 `policy write`를 계속 실행합니다.

```bash
kubectl -n vault exec -i onprem-vault-0 -- vault policy write external-secrets - <<'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
EOF
```

Kubernetes auth method를 활성화하고 클러스터 연결 정보를 설정합니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault auth enable kubernetes
```

`path is already in use` 또는 이미 활성화되어 있다는 에러가 나오면 그 에러는 무시하고, 바로 아래 `auth/kubernetes/config` 설정 명령을 계속 실행합니다.

```bash
kubectl -n vault exec onprem-vault-0 -- sh -c '
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://${KUBERNETES_PORT_443_TCP_ADDR}:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
'
```

마지막으로 External Secrets Operator ServiceAccount용 role을 생성합니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h
```

시간이 좀 지난 뒤에 (3~5분) `ClusterSecretStore` 상태를 다시 확인합니다.

```bash
kubectl get clustersecretstore vault-platform
kubectl describe clustersecretstore vault-platform
```

성공 기준은 `kubectl get` 출력에서 `STATUS=Valid`, `READY=True`가 보이는 것입니다.

```text
NAME             AGE   STATUS   CAPABILITIES   READY
vault-platform   ...   Valid    ReadWrite      True
```

## Vault Secret 입력

Vault 초기화와 Kubernetes auth 설정이 끝난 뒤 Route53 credential, GitHub Actions runner 인증값, Harbor 시스템 고정 secret을 Vault KV v2에 넣습니다.

UI에서 만들 때는 secret path에 `platform/route53`, `platform/github-actions-runner`, `platform/harbor/system`을 입력합니다.

KV v2 API 경로의 `data/`는 Vault가 내부적으로 붙이는 경로이므로 UI secret path에 `data/platform/...`을 입력하지 않습니다.

```bash
kubectl -n vault exec onprem-vault-0 -- vault kv put secret/platform/route53 \
  access-key-id='<aws-access-key-id>' \
  secret-access-key='<aws-secret-access-key>'

kubectl -n vault exec onprem-vault-0 -- vault kv put secret/platform/github-actions-runner \
  github_token='<github-pat>'
```

Harbor의 `secret-key`, `core-secret`, `jobservice-secret`, `registry-http-secret`은 Harbor chart 제약상 16자 문자열이어야 합니다. `registry-htpasswd`는 `REGISTRY_HTPASSWD`로 들어가며, 동일한 registry password에서 매번 같은 htpasswd 문자열을 만들어 넣어야 ArgoCD diff가 흔들리지 않습니다.

```bash
set -euo pipefail

REGISTRY_PASSWORD="$(openssl rand -base64 24)"
htpasswd -nbBC 10 harbor_registry_user "$REGISTRY_PASSWORD" > /tmp/harbor-registry.htpasswd

openssl genrsa -traditional -out /tmp/harbor-token.key 4096
openssl req -x509 -new -key /tmp/harbor-token.key -sha256 -days 3650 \
  -out /tmp/harbor-token.crt \
  -subj "/CN=harbor-token"

test "$(head -n 1 /tmp/harbor-token.key)" = "-----BEGIN RSA PRIVATE KEY-----"

kubectl -n vault exec onprem-vault-0 -- vault kv put secret/platform/harbor/system \
  admin-password="$(openssl rand -base64 24)" \
  secret-key="$(openssl rand -hex 8)" \
  core-secret="$(openssl rand -hex 8)" \
  csrf-key="$(openssl rand -hex 16)" \
  jobservice-secret="$(openssl rand -hex 8)" \
  registry-http-secret="$(openssl rand -hex 8)" \
  registry-password="$REGISTRY_PASSWORD" \
  registry-htpasswd="$(cat /tmp/harbor-registry.htpasswd)" \
  token-tls-key="$(cat /tmp/harbor-token.key)" \
  token-tls-crt="$(cat /tmp/harbor-token.crt)"
```

각 값은 GitOps values의 다음 경로와 property에 대응합니다.

```text
secret/data/platform/route53
  access-key-id: <aws-access-key-id>
  secret-access-key: <aws-secret-access-key>

secret/data/platform/github-actions-runner
  github_token: <github-pat>

secret/data/platform/harbor/system
  admin-password: <harbor-admin-password>
  secret-key: <16-character-secret-key>
  core-secret: <16-character-core-secret>
  csrf-key: <csrf-key>
  jobservice-secret: <16-character-jobservice-secret>
  registry-http-secret: <16-character-registry-http-secret>
  registry-password: <registry-internal-password>
  registry-htpasswd: <htpasswd-line-for-harbor_registry_user>
  token-tls-key: <pem-private-key>
  token-tls-crt: <pem-certificate>
```

시간이 조금 지난 뒤에 (External Secret이 재요청을 할 때까지) Vault 의존 리소스가 회복되는지 확인합니다.

> 만약 즉각 확인하고싶다면, ArgoCD GUI에서 필요한 Secret 리소스들 삭제하고 재생성되게 하자.

```bash
kubectl -n cert-manager get externalsecret route53-credentials
kubectl -n cert-manager get secret route53-credentials-secret
kubectl get clusterissuer letsencrypt-prod
kubectl -n nginx-gateway get secret sonhs-com-tls
kubectl -n arc-runners get externalsecret github-runner-auth
kubectl -n arc-runners get secret onprem-github-runner-auth
kubectl -n harbor get externalsecret harbor-secrets
kubectl -n harbor get secret harbor-secrets
```

## Harbor 초기 비밀번호 확인

ArgoCD처럼 Harbor의 초기 비밀번호를 확인합니다. 로그인 계정은 `admin`입니다.

```bash
kubectl -n harbor get secret onprem-harbor-core \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d
echo
```

이후 비밀번호를 바꾸어 사용합니다.
