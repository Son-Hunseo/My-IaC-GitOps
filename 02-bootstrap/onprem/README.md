# On-Premise Kubernetes Bootstrap (kubespray)

Proxmox VM을 kubespray로 Kubernetes 클러스터로 만들고, Argo CD add-on까지 설치합니다.

kubeadm/containerd/Calico를 직접 설치하던 자체 role들은 kubespray로 대체되었습니다.
kubespray가 다루지 않는 부분(Proxmox 디스크 확장, NFS 패키지, Argo CD add-on)만
`02-bootstrap/*.yml` 플레이북과 `02-bootstrap/roles/` 에 남아 있습니다.

## 구성

- `ansible.cfg`: 02-bootstrap 자체 플레이북용 Ansible 설정입니다. (kubespray는 자기 ansible.cfg를 씁니다)
- `inventory/hosts.yml`: kubespray 그룹 규칙(`kube_control_plane`, `kube_node`, `etcd`, `k8s_cluster`)을 따르는 인벤토리입니다.
- `inventory/group_vars/all/onprem.yml`: **이 환경에서 바꾸는 모든 변수를 담은 단 하나의 파일입니다.**

## 반영된 클러스터 설정

기존 kubeadm 구성의 값을 그대로 옮겼습니다.

| 항목 | 값 | 비고 |
| --- | --- | --- |
| Service CIDR | `10.96.0.0/12` | 기존 `kubernetes_service_subnet` |
| Pod CIDR | `10.244.0.0/16` | 기존 `kubernetes_pod_subnet` |
| 노드당 Pod 서브넷 | `/24` | Pod 대역 기준 최대 256노드 |
| CNI | Calico, VXLAN(Always), IPIP 없음 | 기존 Installation CR의 `encapsulation: VXLAN` |
| Calico blockSize | `26` | 기존 `default-ipv4-ippool` |
| Calico natOutgoing | 활성화 | 기존 `natOutgoing: Enabled` |
| Calico APIServer | 활성화 | 기존 `kind: APIServer` 커스텀 리소스 |
| CRI | containerd | 기존과 동일 |
| kube-proxy | iptables 모드 | kubeadm 기본값과 동일 (kubespray 기본값은 ipvs) |
| API 서버 포트 | `6443` | 기존과 동일 |
| Argo CD | `v2.14.9`, `server.insecure=true` | 기존과 동일 |

### 기존 구성과 달라지는 점

- **Kubernetes 버전이 1.31 → 1.34로 올라갑니다.** kubespray v2.31.0은 1.33~1.35만 지원합니다.
  1.31을 유지하려면 kubespray v2.27 계열로 내려야 하는데, 1년 이상 지난 릴리스라 권장하지 않습니다.
- **etcd가 static pod가 아니라 control plane 노드의 systemd 서비스로 실행됩니다.**
  kubespray의 기본이자 가장 검증된 방식입니다. (`etcd_deployment_type: host`)
- **NodeLocal DNS 캐시가 추가됩니다.** (kubespray 기본값)
- **노드 DNS를 kubespray가 명시적으로 관리합니다.** 아래 "노드 DNS 설정" 참고.

## 노드 DNS 설정

루트 README의 "간헐적 ImagePullBackOff"는 cloud-init이 `/etc/netplan/50-cloud-init.yaml`에
내부 DNS와 `1.1.1.1`을 함께 넣어서, containerd가 `harbor.onprem.arpa`를 물어볼 때
둘 중 하나가 랜덤하게 선택되던 문제였습니다. 당시에는 노드에 직접 들어가 손으로 고쳤습니다.

kubespray는 기본값(`disable_host_nameservers: false`)으로 두면 **노드에 원래 있던
`/etc/resolv.conf` 를 읽어서 그대로 이어붙이므로**, cloud-init이 무엇을 넣어 뒀느냐에 따라
노드마다 결과가 달라집니다. 즉 같은 문제가 그대로 재현될 수 있습니다.

그래서 값을 IaC에 명시해서 결정적으로 만들었습니다.

```yaml
resolvconf_mode: host_resolvconf   # kubespray가 /etc/resolv.conf 를 관리
disable_host_nameservers: true     # 노드에 있던 기존 nameserver는 물려받지 않음
nameservers:                       # 노드가 쓸 nameserver를 전부 여기서 선언
  - 192.168.10.1
upstream_dns_servers:              # CoreDNS/NodeLocal DNS가 외부 도메인을 물어볼 대상
  - 192.168.10.1
```

결과적으로 모든 노드의 `/etc/resolv.conf` 가 아래로 고정됩니다.

```
nameserver 169.254.25.10   # NodeLocal DNS
nameserver 192.168.10.1    # 내부 DNS
```

- `nameservers` 는 `01-infra/onprem/terraform/terraform.tfvars` 의 내부 DNS와 같은 값이어야 합니다.
- **공인 DNS(`1.1.1.1` 등)를 여기에 추가하면 안 됩니다.** 내부 도메인을 모르는 서버가
  선택될 수 있어 원래 문제가 재발합니다. 외부 도메인은 내부 DNS가 상위로 포워딩합니다.
- `upstream_dns_servers` 를 비워 두면 kubespray는 `/etc/resolv.conf` 로 포워딩하는데,
  그 파일 첫 줄이 NodeLocal DNS 자기 자신이라 설정이 자기 참조가 됩니다. 그래서 명시합니다.

> `01-infra/onprem/terraform/terraform.tfvars.example` 의 `dns_servers` 에는 아직
> `1.1.1.1` 이 남아 있습니다. VM 자체의 cloud-init 설정이라 02-bootstrap 범위 밖이지만,
> 위 설정이 노드 `/etc/resolv.conf` 를 덮어쓰므로 클러스터 동작에는 영향이 없습니다.

## 사전 준비

1. `01-infra/onprem` 으로 VM이 생성되어 있어야 합니다.
2. Ansible 실행 호스트에서 대상 VM에 SSH 접속이 가능해야 하고, 접속 사용자가 `sudo` 권한을 가져야 합니다.
3. `inventory/hosts.yml` 의 호스트명, `ansible_host`, `ip`, `ansible_user` 를
   `01-infra/onprem/terraform/terraform.tfvars` 값과 맞춥니다.
4. Windows라면 WSL 안에서 실행합니다.

### 접속 확인

`02-bootstrap` 디렉터리에서 실행합니다.

```bash
ansible -i onprem/inventory/hosts.yml all -m ping
ansible -i onprem/inventory/hosts.yml all -m command -a "whoami" --become
```

두 번째 명령의 결과가 각 VM에서 `root`로 나오면 sudo 권한 상승까지 정상입니다.

## 실행

```bash
cd 02-bootstrap
./scripts/fetch-kubespray.sh     # 최초 1회 (kubespray 클론 + 전용 venv)
./scripts/onprem-bootstrap.sh
```

`onprem-bootstrap.sh` 는 세 단계를 순서대로 실행합니다.

1. `onprem-prepare-nodes.yml` — 루트 디스크 확장, `nfs-common` 설치
2. kubespray `playbooks/cluster.yml` — 클러스터 설치
3. `onprem-install-argocd.yml` — Argo CD add-on 설치

단계별로 따로 실행하려면 아래처럼 하면 됩니다.

```bash
# 1) 사전 준비
ANSIBLE_CONFIG=./onprem/ansible.cfg ansible-playbook \
  -i onprem/inventory/hosts.yml onprem-prepare-nodes.yml

# 2) 클러스터 설치 (kubespray 디렉터리에서, kubespray의 ansible.cfg로)
source ./scripts/kubespray.env
source "${KUBESPRAY_VENV}/bin/activate"
cd "${KUBESPRAY_DIR}"
ansible-playbook -i <저장소경로>/02-bootstrap/onprem/inventory/hosts.yml --become playbooks/cluster.yml

# 3) Argo CD add-on
ANSIBLE_CONFIG=./onprem/ansible.cfg ansible-playbook \
  -i onprem/inventory/hosts.yml onprem-install-argocd.yml
```

## kubeconfig 가져오기

`kubeconfig_localhost: true` 로 설정되어 있어, 설치가 끝나면 아래 경로에 kubeconfig가 생깁니다.

```
02-bootstrap/onprem/inventory/artifacts/admin.conf
```

`kubeconfig_localhost_ansible_host: true` 이므로 server 주소가 control plane의
`ansible_host` 로 들어가 있어 그대로 쓸 수 있습니다.

```bash
export KUBECONFIG=$PWD/onprem/inventory/artifacts/admin.conf
kubectl get nodes
```

기존 kubeconfig와 합치려면 아래처럼 합니다.

```bash
KUBECONFIG=~/.kube/config:$PWD/onprem/inventory/artifacts/admin.conf \
  kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config
kubectl config get-contexts
```

> `inventory/artifacts/` 와 `inventory/credentials/` 는 kubespray가 만드는 로컬 산출물이며
> 자격증명이 들어 있어 `.gitignore` 처리되어 있습니다.

## Argo CD 초기 계정 확인

초기 로그인 계정은 `admin`이며, 초기 비밀번호는 아래 명령으로 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 노드 추가 / 초기화

```bash
# 노드 추가: hosts.yml 에 노드를 추가한 뒤
cd "${KUBESPRAY_DIR}" && ansible-playbook -i <인벤토리> --become playbooks/scale.yml

# 클러스터 초기화 (VM은 유지)
./scripts/onprem-reset.sh
```

## 멱등성

kubespray 플레이북과 Argo CD add-on 플레이북 모두 재실행을 전제로 작성되어 있습니다.
이미 설치된 클러스터에 다시 실행하면 변경된 부분만 반영됩니다.
