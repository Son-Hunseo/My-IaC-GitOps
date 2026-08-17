# 02-bootstrap

`01-infra`가 만든 인프라 위에 Kubernetes 클러스터와 Argo CD를 올리는 Ansible 실행 단위입니다.

| 환경 | 클러스터 설치 | Argo CD add-on |
| --- | --- | --- |
| On-Premise (Proxmox) | kubespray | 설치 |
| AWS EKS | 없음 (관리형 control plane, `01-infra/aws`에서 생성) | 설치 |

Argo CD add-on은 두 환경이 **같은 role(`roles/argocd`)과 같은 변수 이름(`argocd_addon_*`)** 을 사용합니다.
차이는 실행 위치뿐입니다. 온프렘은 control plane 노드에서, EKS는 로컬에서 kubectl을 실행합니다.

## 디렉터리 구조

```
02-bootstrap/
├── scripts/                        # 실행 진입점
│   ├── kubespray.env               #   kubespray 버전 고정
│   ├── fetch-kubespray.sh          #   kubespray 내려받기 + 전용 venv 준비
│   ├── onprem-bootstrap.sh         #   온프렘 전체 실행 (사전준비 → kubespray → Argo CD)
│   ├── onprem-reset.sh             #   온프렘 클러스터 초기화
│   └── aws-bootstrap.sh            #   EKS Argo CD add-on 설치
├── onprem-prepare-nodes.yml        # 02-bootstrap 자체 플레이북 (kubespray가 다루지 않는 부분)
├── onprem-install-argocd.yml       #   roles/ 와 같은 위치에 두어야 role이 자동으로 잡힙니다
├── aws-install-argocd.yml
├── roles/                          # 온프렘/EKS 공용 role
│   ├── argocd/
│   └── disk-extend/
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
`argocd_addon_*` 등)를 함께 선언하므로, 환경 설정을 볼 곳이 한 군데뿐입니다.

> `argocd_addon_*` 접두사를 쓰는 이유: kubespray에도 `argocd_version` 변수가 있고
> 이 값이 download checksum 조회에 쓰이기 때문에, 같은 이름을 쓰면 kubespray 실행이 깨집니다.

## 사전 준비

- 실행 호스트: macOS 또는 Linux(Ubuntu). Windows라면 **WSL 안에서** 실행합니다.
- 대상 VM에 SSH 접속이 가능하고, 접속 사용자가 `sudo` 권한을 가져야 합니다.
- `git`, `python3`, `python3-venv` 가 설치되어 있어야 합니다.

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
aws eks update-kubeconfig --region <region> --name <cluster-name>
./scripts/aws-bootstrap.sh
```

자세한 내용은 [aws/README.md](aws/README.md) 를 보세요.

## 다음 단계

Argo CD가 올라오면 `03-k8s-clusters`의 root `Application`만 적용하면 됩니다.
MetalLB, Gateway, cert-manager, 모니터링 등 나머지 플랫폼 컴포넌트는 모두
Argo CD App-of-Apps가 동기화하므로 kubespray add-on으로는 설치하지 않습니다.
