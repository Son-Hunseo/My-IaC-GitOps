# AWS EKS Platform GitOps

이 디렉터리는 이미 부트스트랩이 끝난 AWS EKS 클러스터의 플랫폼 구성요소를 Argo CD로 설치합니다.
Argo CD 자체 설치는 `02-bootstrap/aws` 단계의 책임이며, 여기서는 Argo CD가 동기화할 운영 컴포넌트만 다룹니다.

## 이 계층이 다루지 않는 것

설치 후 사실상 손댈 일이 없는 플랫폼 기반 컴포넌트는 앞 계층이 설치합니다.

| 컴포넌트 | 설치 위치 | 설정 파일 |
| --- | --- | --- |
| 표준 Gateway API CRDs (`gateway.networking.k8s.io`) | `02-bootstrap` (자체 role) | `02-bootstrap/aws/inventory/group_vars/all/aws.yml` |
| metrics-server | `02-bootstrap` (자체 role) | 〃 |
| Argo CD | `02-bootstrap` (자체 role) | 〃 |
| AWS EBS CSI Driver | `01-infra` (terraform EKS 관리형 add-on) | `01-infra/aws/terraform/main.tf` |

ALB 전용 Gateway CRD(`gateway.k8s.aws`)는 AWS Load Balancer Controller 버전과 함께 움직이므로
`overlays/apps/aws-load-balancer-controller-gateway-crds.yaml` 로 계속 이 계층에서 관리합니다.

`Gateway`, `HTTPRoute`, `LoadBalancerConfiguration` 처럼 **위 컴포넌트를 사용하는 리소스**도
환경에 따라 자주 바뀌므로 계속 이 계층에 있습니다.

중요: `kubectl apply -f 03-k8s-clusters/aws`로 한 번에 설치하지 않습니다.
`argocd/projects/platform.yaml`과 root `Application`을 적용하고, root `Application`이 하위 platform component들을 동기화하게 만듭니다.

## 구성

- `argocd/projects/platform.yaml`: Argo CD `AppProject`입니다.
- `argocd/applications/platform.yaml`: AWS EKS root `Application`입니다.
- `overlays/`: AWS EKS 클러스터 전용 Kubernetes 리소스와 child `Application`입니다.
- `values/`: Helm chart에 전달할 AWS EKS values 파일입니다.

## 사전 조건

Argo CD가 먼저 설치되어 있어야 합니다.

```bash
kubectl get namespace argocd
kubectl -n argocd get pods
```

## 사전 설정

AWS 플랫폼 구성을 본인 원격 Git 저장소에서 동기화하려면 아래 `repoURL` 값을 실제 원격 URL로 바꿔야 합니다.

수정 대상은 다음과 같습니다.

```text
03-k8s-clusters/aws/argocd/applications/platform.yaml
03-k8s-clusters/aws/overlays/apps/alb-config.yaml
03-k8s-clusters/aws/overlays/apps/aws-load-balancer-controller.yaml
  - sources[0].repoURL
  - sources[2].repoURL
03-k8s-clusters/aws/overlays/apps/external-gateway.yaml
03-k8s-clusters/aws/overlays/apps/external-secrets-aws-store.yaml
03-k8s-clusters/aws/overlays/apps/external-secrets.yaml
  - sources[1].repoURL
03-k8s-clusters/aws/overlays/apps/grafana.yaml
  - sources[1].repoURL
03-k8s-clusters/aws/overlays/apps/internal-gateway.yaml
03-k8s-clusters/aws/overlays/apps/prometheus.yaml
  - sources[1].repoURL
```

다음 `repoURL` 값들은 외부 Helm chart 또는 CRD 원본이므로 본인 Git 저장소 URL로 바꾸지 않습니다.

```text
https://aws.github.io/eks-charts
https://charts.external-secrets.io
https://grafana.github.io/helm-charts
https://prometheus-community.github.io/helm-charts
https://github.com/kubernetes-sigs/aws-load-balancer-controller.git
```

먼저 현재 kubeconfig가 가리키는 EKS cluster name과 region을 확인합니다.

```bash
kubectl config current-context
```

cluster name과 region을 변수로 지정합니다.

```bash
CLUSTER_NAME=gitops-eks-dev
AWS_REGION=ap-northeast-2
```

AWS Load Balancer Controller values에 넣을 VPC ID를 AWS CLI로 조회합니다.

```bash
VPC_ID=$(aws eks describe-cluster \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

printf 'AWS_REGION=%s\nCLUSTER_NAME=%s\nVPC_ID=%s\n' \
  "${AWS_REGION}" "${CLUSTER_NAME}" "${VPC_ID}"
```

AWS Load Balancer Controller IRSA role ARN은 Terraform output에서 확인합니다.

```bash
cd 01-infra/aws/terraform
AWS_LOAD_BALANCER_CONTROLLER_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)
cd -

printf 'AWS_LOAD_BALANCER_CONTROLLER_ROLE_ARN=%s\n' \
  "${AWS_LOAD_BALANCER_CONTROLLER_ROLE_ARN}"
```

조회한 값으로 AWS Load Balancer Controller values를 바꿉니다.

```text
03-k8s-clusters/aws/values/aws-load-balancer-controller-values.yaml
```

수정할 값은 다음과 같습니다.

- `clusterName`
- `region`
- `vpcId`
- `serviceAccount.annotations.eks.amazonaws.com/role-arn`

예시는 다음과 같습니다.

```yaml
clusterName: gitops-eks-dev
region: ap-northeast-2
vpcId: vpc-xxxxxxxxxxxxxxxxx

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<aws-load-balancer-controller-role>
```

AWS Internal Gateway의 ALB 설정도 환경에 맞게 확인하고 바꿉니다.

```text
03-k8s-clusters/aws/overlays/internal-gateway/load-balancer-configuration.yaml
```

집이나 사무실에서만 접근할 public ALB 실습이면 현재 공인 IP를 조회해서 `/32`로 넣습니다.

```bash
MY_PUBLIC_IP=$(curl -fsSL https://checkip.amazonaws.com | tr -d '\n')
printf 'MY_PUBLIC_CIDR=%s/32\n' "${MY_PUBLIC_IP}"
```

수정할 값은 다음과 같습니다.

- `spec.sourceRanges`: 접근을 허용할 집 공인 IP, 사무실 NAT, VPN egress CIDR. 예: `${MY_PUBLIC_IP}/32`

AWS Secrets Manager 연동을 쓸 경우 External Secrets Operator IRSA role ARN을 Terraform output에서 확인합니다.

```bash
cd 01-infra/aws/terraform
EXTERNAL_SECRETS_ROLE_ARN=$(terraform output -raw external_secrets_role_arn)
cd -

printf 'EXTERNAL_SECRETS_ROLE_ARN=%s\n' "${EXTERNAL_SECRETS_ROLE_ARN}"
```

조회한 값으로 External Secrets Operator values를 바꿉니다.

```text
03-k8s-clusters/aws/values/external-secrets-values.yaml
```

수정할 값은 다음과 같습니다.

- `serviceAccount.annotations.eks.amazonaws.com/role-arn`

예시는 다음과 같습니다.

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<external-secrets-role>
```

## External Gateway

AWS overlay는 `sonhs.com`, `*.sonhs.com` Gateway listener를 public ALB로 만들고, HTTPS 인증서는 ACM public certificate를 사용합니다.
AWS ALB Gateway의 HTTPS listener는 Kubernetes Secret `certificateRefs`를 사용하지 않으므로 External Gateway의 `LoadBalancerConfiguration`에는 ACM 인증서 ARN이 필요합니다.

ACM 인증서가 아직 없다면 EKS와 ALB를 생성할 region에서 `sonhs.com`, `*.sonhs.com`을 포함하는 public certificate를 먼저 요청합니다.

```bash
aws acm request-certificate \
  --region ap-northeast-2 \
  --domain-name sonhs.com \
  --subject-alternative-names "*.sonhs.com" \
  --validation-method DNS
```

출력된 `CertificateArn`으로 DNS 검증 레코드를 확인합니다.

```bash
aws acm describe-certificate \
  --region ap-northeast-2 \
  --certificate-arn <certificate-arn> \
  --query 'Certificate.DomainValidationOptions[*].ResourceRecord'
```

표시된 CNAME record를 `sonhs.com` Route53 Hosted Zone에 추가하고 인증서 상태가 `ISSUED`가 될 때까지 기다립니다.

```bash
aws acm describe-certificate \
  --region ap-northeast-2 \
  --certificate-arn <certificate-arn> \
  --query 'Certificate.Status' \
  --output text
```

ACM 인증서는 ALB와 같은 region에 있어야 합니다.

수정 대상은 다음 파일입니다.

```text
03-k8s-clusters/aws/overlays/external-gateway/load-balancer-configuration.yaml
```

`REPLACE_ACM_CERTIFICATE_ARN_FOR_SONHS_COM`을 `sonhs.com`, `*.sonhs.com`을 포함하는 ACM 인증서 ARN으로 바꿉니다.

```yaml
defaultCertificate: arn:aws:acm:ap-northeast-2:<account-id>:certificate/<certificate-id>
```

필요하면 다음 값도 환경에 맞게 조정합니다.

- `spec.sourceRanges`: 외부 공개 Gateway이면 `0.0.0.0/0`, 제한 공개가 필요하면 허용 CIDR 목록
- `spec.tags`: 필요한 경우 조직/비용/운영 태그

공개 DNS는 External Gateway가 생성한 ALB DNS name 또는 그 앞의 Route53 alias를 가리켜야 합니다.

```text
sonhs.com      -> <external-gateway-alb>
www.sonhs.com  -> <external-gateway-alb>
*.sonhs.com    -> <external-gateway-alb>
```

## 변경 사항 Push

`repoURL`, values, overlay 설정을 수정했다면 원격 Git 저장소에 push합니다.
Argo CD는 원격 Git 저장소의 내용을 기준으로 동기화합니다.

```bash
git status --short
git diff -- 03-k8s-clusters/aws
git add 03-k8s-clusters/aws
git commit -m "Configure AWS Kubernetes platform applications"
git push
```

이미 별도 커밋 흐름을 사용 중이면 해당 방식으로 push하면 됩니다.

## Root Application 적용

프로젝트 루트에서 실행합니다.

```bash
kubectl apply -f 03-k8s-clusters/aws/argocd/projects/platform.yaml
kubectl apply -f 03-k8s-clusters/aws/argocd/applications/platform.yaml
```
