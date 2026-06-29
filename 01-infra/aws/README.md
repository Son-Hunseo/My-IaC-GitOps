# AWS EKS Infrastructure

## 목적

이 실행 단위는 AWS 위에 EKS 기반 인프라 환경을 생성합니다.

포함 범위:

- EKS용 VPC
- public subnet과 private subnet
- Internet Gateway
- NAT Gateway
- route table
- EKS control plane
- EKS managed node group 1개
- Amazon EBS CSI Driver EKS add-on
- EBS CSI Driver용 IRSA role과 EKS OIDC provider
- AWS Load Balancer Controller용 IRSA role과 IAM policy
- External Secrets Operator용 IRSA role과 AWS Secrets Manager read policy
- worker node 2대 기본 구성
- worker instance type `t3.large`

포함하지 않는 범위:

- Kubernetes workload
- Helm chart
- Argo CD 또는 Flux
- 애플리케이션 배포
- Kubernetes `StorageClass` 리소스
- External Gateway용 ACM public certificate

## 전제 조건

1. Terraform 1.6 이상
2. AWS CLI 또는 동등한 AWS 인증 설정
3. EKS, EC2, IAM, VPC 리소스를 생성할 수 있는 AWS 권한
4. 선택한 region에서 사용 가능한 최소 2개 Availability Zone

## AWS 인증

```bash
aws configure
```

- 엑세스 키 ID, Secret 엑세스 키 등을 입력해서 자격 증명하기

## 설정

아래 Terraform 명령은 이 README가 있는 `01-infra/aws` 기준으로 `terraform` 디렉터리에서 실행합니다.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

| 변수 | 설명 |
| --- | --- |
| `aws_region` | EKS를 생성할 AWS region |
| `cluster_name` | EKS cluster 이름 |
| `cluster_version` | EKS Kubernetes version |
| `vpc_cidr` | VPC CIDR |
| `public_subnet_cidrs` | public subnet CIDR 목록 |
| `private_subnet_cidrs` | private subnet CIDR 목록 |
| `availability_zones` | subnet을 배치할 AZ 목록 |
| `single_nat_gateway` | NAT Gateway 1개만 사용할지 여부 |
| `endpoint_public_access` | EKS public API endpoint 활성화 여부 |
| `public_access_cidrs` | public API endpoint 접근 허용 CIDR |
| `node_instance_types` | worker node instance type 목록 |
| `node_desired_size` | desired worker node 수 |
| `ebs_csi_addon_version` | EBS CSI Driver add-on version. 비워 두면 AWS 기본값 사용 |
| `external_secrets_secret_arns` | External Secrets Operator가 읽을 수 있는 Secrets Manager secret ARN 목록. 비워 두면 `<cluster_name>-*` secret으로 제한 |
| `external_secrets_kms_key_arns` | 고객 관리형 KMS key로 암호화한 secret을 읽을 때 허용할 KMS key ARN 목록 |

`terraform.tfvars`에서 region, CIDR, AZ, cluster name, endpoint 접근 CIDR 등을 실제 환경에 맞게 조정합니다.

## 초기화

```bash
terraform init
```

## 포맷 및 검증

```bash
terraform fmt
terraform validate
```

## 계획 확인

```bash
terraform plan
```

생성될 VPC, subnet, NAT Gateway, IAM role, EKS cluster, managed node group을 확인합니다.

## 적용

```bash
terraform apply
```

적용 후 주요 출력값을 확인합니다.

```bash
terraform output
terraform output update_kubeconfig_command
terraform output aws_load_balancer_controller_role_arn
terraform output external_secrets_role_arn
```

## EKS에서 kubeconfig 가져오는 법

AWS CLI 인증이 먼저 완료되어 있어야 합니다.

```bash
aws sts get-caller-identity
```

기본 프로파일로 kubeconfig를 생성하거나 병합합니다.

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name CLUSTER_NAME
kubectl get nodes
```

## 스토리지

Terraform은 EKS 클러스터에 Amazon EBS CSI Driver add-on을 설치하고, 해당 add-on이 사용할 IRSA role을 생성합니다. (Amazon EBS CSI Driver가 실행되는 Kubernetes ServiceAccount에 IAM Role을 연결해서 EBS API를 호출할 권한을 주는 것이다)

Kubernetes `StorageClass`는 GitOps 계층의 책임으로 두며, `03-k8s-clusters/aws/overlays/storage`에서 `gp3` 기본 `StorageClass`를 제공합니다.

따라서 AWS overlay의 Prometheus/Grafana PVC는 기본적으로 암호화된 `gp3` EBS volume으로 동적 프로비저닝됩니다.

## GitOps 계층용 IRSA role

Terraform은 `03-k8s-clusters` AWS overlay가 사용할 다음 IRSA role도 함께 생성합니다.

`aws_load_balancer_controller_role_arn`
- `kube-system/aws-load-balancer-controller` ServiceAccount용
- AWS Load Balancer Controller가 ALB/NLB 관련 AWS 리소스를 생성/수정/삭제 하기 위함

`external_secrets_role_arn`
- `external-secrets/external-secrets` ServiceAccount용
- External Secrets Operator가 AWS Secrets Manager 또는 SSM Parameter Store에서 값을 읽어 Kubernetes Secret으로 동기화

## 삭제

원래 현재 `01-infra` 단계까지만 진행했을 경우, `terraform destroy`만 쓰면 리소스가 정리된다.

그러나, `03-k8s-clusters` 단계 이상 진행했을 경우 깔끔하게 정리되지 않는다.

왜냐하면 ALB, 관련 Security Group, 동적 EBS volume은 Terraform이 직접 생성한 리소스가 아니라 Kubernetes controller와 GitOps 계층이 생성한 리소스이기 때문이다.

따라서 Terraform destroy 전에 Argo CD가 관리하는 AWS platform 리소스를 먼저 정리합니다.

먼저 삭제 대상을 확인합니다. 이 명령은 조회만 수행합니다.

```bash
kubectl get applications.argoproj.io -n argocd
```

root Application을 삭제해서 child Application이 다시 생성되지 않게 합니다.

```bash
kubectl delete applications.argoproj.io aws-platform -n argocd --ignore-not-found
```

그 다음 AWS child Application에 Argo CD resources finalizer를 붙이고 삭제합니다.
이 finalizer가 있어야 Application 삭제 시 Argo CD가 해당 Application이 생성한 Kubernetes 리소스도 함께 정리합니다.

```bash
for app in \
  aws-external-gateway \
  aws-internal-gateway \
  aws-grafana \
  aws-prometheus \
  aws-external-secrets-aws-store \
  aws-external-secrets \
  aws-load-balancer-controller \
  aws-alb-config \
  aws-load-balancer-controller-gateway-crds \
  aws-gateway-api-crds
do
  kubectl patch applications.argoproj.io "$app" -n argocd --type=merge \
    -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' || true
  kubectl delete applications.argoproj.io "$app" -n argocd --ignore-not-found
done
```

정리가 끝났는지 확인합니다.

```bash
kubectl get gateway -A
kubectl get pvc -A
kubectl get applications.argoproj.io -n argocd
```

ALB, 관련 Security Group, PVC/EBS volume이 정리된 것을 확인한 뒤 Terraform 리소스를 삭제합니다.

```bash
terraform destroy
```

## Notes and limitations

- 기본값은 개발/검증 환경에 맞춘 비용 절감형 `single_nat_gateway = true`입니다.
- `cluster_version` 기본값은 2026-06-01 기준 AWS EKS standard support에 포함된 `1.35`입니다. 실제 적용 전 AWS 문서나 `aws eks describe-cluster-versions`로 사용 가능 버전을 확인하십시오.
- 운영 환경에서는 AZ별 NAT Gateway 구성을 검토하십시오.
- `public_access_cidrs = ["0.0.0.0/0"]`는 편의 기본값이며, 실제 환경에서는 관리자 IP 대역으로 제한하는 것을 권장합니다.
- `203.0.113.0/24`, `198.51.100.0/24`, `192.0.2.0/24`는 문서 예시용 TEST-NET 대역이므로 EKS public API endpoint 허용 CIDR로 사용할 수 없습니다.
- EKS add-on 버전 pinning, cluster autoscaler 또는 Karpenter는 이 실행 단위에서 다루지 않습니다.
- EBS CSI Driver add-on version은 기본적으로 AWS가 cluster version에 맞는 값을 선택합니다. 고정이 필요하면 `ebs_csi_addon_version`을 지정하십시오.
- AWS Load Balancer Controller IAM policy는 chart targetRevision `3.4.0`에 맞춰 공식 reference policy를 포함합니다. controller chart를 올릴 때 `aws-load-balancer-controller-iam-policy.json`도 같이 확인하십시오.
- Terraform state는 초기에는 로컬에 생성됩니다. 협업 환경에서는 원격 backend를 별도로 추가하십시오.
