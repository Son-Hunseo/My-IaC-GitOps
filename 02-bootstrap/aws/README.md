# AWS EKS Bootstrap

`01-infra/aws` 단계에서 이미 생성된 AWS EKS 클러스터에 플랫폼 기반 add-on을 설치하는 실행 단위입니다.

EKS는 관리형 control plane이므로 **클러스터 설치(kubespray) 단계가 없습니다.**
그리고 **kubespray의 내장 add-on도 쓸 수 없습니다.** kubespray의 add-on role은 전부
`kube_control_plane` 노드에 SSH해서 그 노드의 `kubectl`을 실행하는 구조인데,
EKS에는 그런 노드가 없기 때문입니다.

그래서 온프렘이 kubespray 내장 add-on으로 얻는 것들을 여기서는 `02-bootstrap/roles/` 의
자체 role로 설치하고, 변수 이름과 절차는 최대한 온프렘과 맞췄습니다.

## 설치하는 add-on

| add-on | 버전 | role |
| --- | --- | --- |
| kubeconfig 등록 | - | `roles/kubeconfig-eks` |
| Gateway API CRDs (standard) | `v1.5.0` | `roles/gateway-api-crds` |
| metrics-server | `v0.8.1` | `roles/metrics-server` |
| Argo CD | `v2.14.9` | `roles/argocd` (온프렘과 공용) |

이 순서대로 실행됩니다. kubeconfig를 먼저 등록해야 뒤따르는 role들이 바로 `kubectl`을 쓸 수 있습니다.

Gateway API 버전은 AWS Load Balancer Controller v3.4.0 문서가 요구하는 `v1.5.0`으로 고정했습니다.
(온프렘은 kubespray가 `v1.5.1`을 설치합니다. NGINX Gateway Fabric 2.6.3의 요구 버전입니다)

### 여기서 설치하지 않는 것

**AWS EBS CSI Driver**는 `01-infra/aws` 의 terraform이 설치합니다. (`aws_eks_addon.ebs_csi`)

IRSA role ARN이 필요한 EKS 관리형 add-on이라 IAM role을 만드는 계층에 같이 두는 편이 자연스럽고,
버전 관리도 AWS가 해 줍니다. 설치 여부는 아래 명령으로 확인합니다.

```bash
aws eks list-addons --cluster-name <cluster-name> --region <region>
kubectl -n kube-system get deployment ebs-csi-controller
```

**cert-manager**는 AWS overlay가 ACM public certificate를 사용하므로 필요 없고,
**MetalLB**는 ALB/NLB가 있는 EKS에 해당하지 않습니다.

## 구성

- `ansible.cfg`: AWS EKS bootstrap용 Ansible 설정입니다.
- `inventory/eks.yml`: 로컬 실행 인벤토리입니다.
- `inventory/group_vars/all/aws.yml`: **이 환경에서 바꾸는 모든 변수를 담은 단 하나의 파일입니다.**

플레이북과 role은 `02-bootstrap` 아래에 있고 Argo CD role은 온프렘과 공유합니다.

- `02-bootstrap/aws-install-addons.yml`
- `02-bootstrap/roles/`

## 사전 준비

1. 실행 호스트에 `aws` CLI와 `kubectl` 이 있어야 하고, AWS 자격증명이 설정되어 있어야 합니다.

   ```bash
   aws sts get-caller-identity
   ```

2. `inventory/group_vars/all/aws.yml` 의 클러스터 정보를 맞춥니다.

   ```yaml
   eks_cluster_name: gitops-eks-dev
   eks_region: ap-northeast-2
   ```

   값은 terraform output에서 확인합니다.

   ```bash
   cd 01-infra/aws/terraform
   terraform output -raw cluster_name
   ```

`aws eks update-kubeconfig` 는 `kubeconfig-eks` role이 대신 실행하므로 **직접 실행할 필요가 없습니다.**
이미 kubeconfig를 손으로 준비해 두었다면 `kubeconfig_eks_enabled: false` 로 두면 됩니다.

## 실행

`02-bootstrap` 디렉터리에서 실행합니다.

```bash
./scripts/aws-bootstrap.sh
```

스크립트 없이 직접 실행하려면:

```bash
ANSIBLE_CONFIG=./aws/ansible.cfg ansible-playbook \
  -i aws/inventory/eks.yml aws-install-addons.yml
```

특정 add-on만 다시 실행하려면 태그를 씁니다.

```bash
./scripts/aws-bootstrap.sh --tags metrics-server
./scripts/aws-bootstrap.sh --tags argocd
```

사용 가능한 태그: `kubeconfig`, `gateway-api-crds`, `metrics-server`, `argocd`

## 주요 변수

모두 `inventory/group_vars/all/aws.yml` 한 파일에서 관리합니다.

| 변수 | 설명 |
| --- | --- |
| `eks_cluster_name` | 대상 EKS 클러스터 이름입니다. kubeconfig 컨텍스트 이름으로도 쓰입니다. |
| `eks_region` | EKS 클러스터가 있는 리전입니다. |
| `eks_kube_context` | add-on role들이 사용할 kubeconfig 컨텍스트입니다. |
| `eks_kubeconfig` | kubeconfig 경로입니다. `KUBECONFIG` 가 있으면 그 값을 씁니다. |
| `kubeconfig_eks_enabled` | `aws eks update-kubeconfig` 자동 실행 여부입니다. |
| `gateway_api_addon_version` | 설치할 Gateway API 릴리스입니다. |
| `gateway_api_addon_channel` | `standard` 또는 `experimental` 입니다. |
| `metrics_server_addon_version` | 설치할 metrics-server 버전입니다. |
| `argocd_addon_version` | 설치할 Argo CD manifest 버전입니다. |
| `argocd_addon_namespace` | Argo CD를 설치할 네임스페이스입니다. |
| `argocd_addon_server_insecure` | 테스트용 HTTP Gateway 뒤에서 Argo CD HTTPS 리다이렉트를 끌지 여부입니다. |

## 설치 확인

```bash
kubectl config current-context
kubectl get crd | grep gateway.networking.k8s.io
kubectl top nodes
kubectl -n argocd get pods
```

## Argo CD 초기 비밀번호 확인

초기 로그인 계정은 `admin`이며, 초기 비밀번호는 아래 명령으로 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
