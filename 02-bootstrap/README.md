# 02-bootstrap

`01-infra`가 만든 인프라 위에 Kubernetes 클러스터와 플랫폼 기반 add-on을 올리는 Ansible 실행 단위입니다.

| 환경 | 클러스터 설치 | add-on 설치 방식 |
| --- | --- | --- |
| On-Premise (Proxmox) | kubespray | kubespray 내장 add-on + 자체 role |
| AWS EKS | 없음 (관리형 control plane, `01-infra/aws`에서 생성) | 자체 role만 |

## 이 계층이 설치하는 add-on

설치 후 사실상 손댈 일이 없는 플랫폼 기반 컴포넌트를 이 계층에서 설치합니다.
GitOps로 관리해도 diff가 생기지 않는 것들이라 `03-k8s-clusters`에서 내렸습니다.

| add-on | On-Premise | AWS EKS |
| --- | --- | --- |
| Argo CD | 자체 role `roles/argocd` (v2.14.9) | 자체 role `roles/argocd` (v2.14.9) |
| Gateway API CRDs | kubespray `gateway_api_enabled` (v1.5.1) | 자체 role `roles/gateway-api-crds` (v1.5.0) |
| metrics-server | kubespray `metrics_server_enabled` (v0.8.1) | 자체 role `roles/metrics-server` (v0.8.1) |
| cert-manager | kubespray `cert_manager_enabled` (v1.15.3) | 없음 (ACM 인증서 사용) |
| MetalLB | kubespray `metallb_enabled` (v0.13.9) | 없음 (ALB/NLB 사용) |
| kubeconfig 등록 | 자체 role `roles/kubeconfig-merge` | 자체 role `roles/kubeconfig-eks` |

`03-k8s-clusters`는 이 위에 얹히는(자주 바뀌는) 컴포넌트만 담당합니다.
External Secrets, Vault, Harbor, NGINX Gateway Fabric, Prometheus/Grafana, ARC, Gateway/HTTPRoute,
ClusterIssuer, ALB 전용 Gateway CRD(`gateway.k8s.aws`) 등이 여기에 해당합니다.

### 왜 AWS는 kubespray를 쓰지 않는가

kubespray의 add-on role은 전부 `groups['kube_control_plane'][0]` 노드에 SSH해서
그 노드의 `kubectl`을 실행하는 구조입니다.
EKS는 관리형 control plane이라 그런 노드가 없으므로 `metrics_server_enabled` 같은
변수 자체가 동작하지 않습니다.

그래서 AWS는 온프렘이 kubespray로 얻는 것들을 `roles/` 의 자체 role로 설치하고,
변수 이름과 절차는 최대한 온프렘과 맞춰 두 환경을 같은 방식으로 다룹니다.

### AWS EBS CSI Driver

`02-bootstrap`이 아니라 **`01-infra/aws`의 terraform**이 설치합니다. (`aws_eks_addon.ebs_csi`)

IRSA role ARN이 필요한 EKS 관리형 add-on이라 IAM role을 만드는 계층에 같이 두는 편이 자연스럽고,
버전 관리도 AWS가 해 줍니다. 02-bootstrap으로 옮기면 terraform output에서 ARN을 받아
넘겨야 하고 self-managed 설치가 되므로 그대로 두었습니다.

## 디렉터리 구조

```
02-bootstrap/
├── scripts/                        # 실행 진입점
│   ├── kubespray.env               #   kubespray 버전 고정
│   ├── fetch-kubespray.sh          #   kubespray 내려받기 + 전용 venv 준비
│   ├── onprem-bootstrap.sh         #   온프렘 전체 실행 (사전준비 → kubespray → 자체 add-on)
│   ├── onprem-reset.sh             #   온프렘 클러스터 초기화
│   └── aws-bootstrap.sh            #   EKS add-on 설치
├── onprem-prepare-nodes.yml        # 02-bootstrap 자체 플레이북 (kubespray가 다루지 않는 부분)
├── onprem-install-addons.yml       #   roles/ 와 같은 위치에 두어야 role이 자동으로 잡힙니다
├── aws-install-addons.yml
├── roles/                          # 온프렘/EKS 공용 role
│   ├── argocd/                     #   두 환경 공용
│   ├── disk-extend/                #   온프렘 전용
│   ├── kubeconfig-merge/           #   온프렘 전용 (kubespray 산출물을 ~/.kube/config 에 병합)
│   ├── kubeconfig-eks/             #   AWS 전용 (aws eks update-kubeconfig)
│   ├── gateway-api-crds/           #   AWS 전용 (온프렘은 kubespray가 담당)
│   └── metrics-server/             #   AWS 전용 (온프렘은 kubespray가 담당)
├── kubespray-sample/               # 업스트림 sample inventory 복사본 (참조 전용, 미적용)
├── onprem/
│   ├── ansible.cfg
│   └── inventory/
│       ├── hosts.yml
│       └── group_vars/all/onprem.yml   # ★ 온프렘의 단 하나의 오버라이드 파일
└── aws/
    ├── ansible.cfg
    └── inventory/
        ├── eks.yml
        └── group_vars/all/aws.yml      # ★ EKS의 단 하나의 오버라이드 파일
```

## 설정 방식: 단일 오버라이드 파일

kubespray는 모든 기본값을 `roles/kubespray_defaults/defaults/main/` 에 가지고 있고,
`inventory/sample/group_vars/` 는 사실상 "바꿀 수 있는 값 목록 문서"입니다.

그래서 이 저장소는 sample 계층을 인벤토리로 복사해서 파일마다 값을 고치는 대신,

- `kubespray-sample/` 에 업스트림 sample을 **손대지 않고 복사만** 해 두고 (참조 전용),
- 실제로 바꾸는 값은 환경별로 **단 하나의 파일**에 모아 선언합니다.

인벤토리 `group_vars` 는 role `defaults` 보다 우선순위가 높으므로, 오버라이드 파일의 값이 항상 이깁니다.

이 파일 하나에 kubespray 변수와 02-bootstrap 자체 add-on 변수(`disk_extend_enabled`,
`argocd_addon_*`, `kubeconfig_merge_*` 등)를 함께 선언하므로, 환경 설정을 볼 곳이 한 군데뿐입니다.

> 자체 role의 변수에 `argocd_addon_`, `metrics_server_addon_`, `gateway_api_addon_` 처럼
> `_addon_` 접두사를 쓰는 이유: kubespray에도 `argocd_version`, `metrics_server_version`,
> `gateway_api_version` 같은 같은 이름의 변수가 있고, 그중 일부는 download checksum 조회에
> 쓰이기 때문에 이름이 겹치면 kubespray 실행이 깨집니다.

## kubeconfig 자동 설정

두 환경 모두 add-on 설치 과정에서 **Ansible 실행 호스트의 `~/.kube/config`** 에
클러스터 컨텍스트를 등록합니다. 기존 컨텍스트는 지워지지 않습니다.

| 환경 | 방식 | 기본 컨텍스트 이름 |
| --- | --- | --- |
| On-Premise | kubespray 산출물(`inventory/artifacts/admin.conf`)을 병합 | `onprem-admin` |
| AWS EKS | `aws eks update-kubeconfig --alias` | `eks_cluster_name` 값 |

필요 없으면 오버라이드 파일에서 `kubeconfig_merge_enabled` / `kubeconfig_eks_enabled` 를
`false` 로 두면 됩니다.

## 사전 준비

- 실행 호스트: macOS 또는 Linux(Ubuntu). Windows라면 **WSL 안에서** 실행합니다.
- 대상 VM에 SSH 접속이 가능하고, 접속 사용자가 `sudo` 권한을 가져야 합니다. (온프렘)
- `git`, `python3`, `python3-venv` 가 설치되어 있어야 합니다.
- `kubectl` 이 실행 호스트에 있어야 합니다. (kubeconfig 병합, AWS add-on 설치에 사용)
- AWS는 `aws` CLI와 자격증명이 필요합니다.

kubespray는 자기 자신이 요구하는 Ansible 버전이 있어서, `fetch-kubespray.sh` 가
전용 virtualenv를 따로 만듭니다. `PREPARE.md` 로 설치한 시스템 Ansible과 섞이지 않습니다.

> kubespray 저장소는 파일 경로가 매우 길어 Windows 파일시스템(`/mnt/c` 포함)에서는
> 체크아웃이 "Filename too long"으로 실패합니다. 그래서 `KUBESPRAY_DIR` 기본값을
> 리눅스 홈(`$HOME/.kubespray/<version>`)으로 두었습니다.

## 실행

### On-Premise

```bash
cd 02-bootstrap
./scripts/fetch-kubespray.sh
# inventory/hosts.yml 과 group_vars/all/onprem.yml 을 환경에 맞게 수정한 뒤
./scripts/onprem-bootstrap.sh
```

자세한 내용은 [onprem/README.md](onprem/README.md) 를 보세요.

### AWS EKS

```bash
cd 02-bootstrap
# aws/inventory/group_vars/all/aws.yml 의 eks_cluster_name, eks_region 을 맞춘 뒤
./scripts/aws-bootstrap.sh
```

자세한 내용은 [aws/README.md](aws/README.md) 를 보세요.

## 다음 단계

Argo CD가 올라오면 `03-k8s-clusters`의 root `Application`만 적용하면 됩니다.
