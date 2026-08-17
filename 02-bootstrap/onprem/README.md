# On-Premise Kubernetes Bootstrap (kubespray)

Proxmox VM을 kubespray로 Kubernetes 클러스터로 만들고, 플랫폼 기반 add-on까지 설치합니다.

kubeadm/containerd/Calico를 직접 설치하던 자체 role들은 kubespray로 대체되었습니다.
kubespray가 다루지 않는 부분(Proxmox 디스크 확장, NFS 패키지, Argo CD, kubeconfig 병합)만
`02-bootstrap/*.yml` 플레이북과 `02-bootstrap/roles/` 에 남아 있습니다.

## 설치하는 add-on

설치 후 사실상 손댈 일이 없는 플랫폼 기반 컴포넌트는 GitOps로 관리해도 diff가 생기지 않으므로
`03-k8s-clusters`에서 내려 이 계층에서 설치합니다.

| add-on | 버전 | 설치 방식 | 관련 변수 |
| --- | --- | --- | --- |
| Gateway API CRDs (standard) | `v1.5.1` | kubespray 내장 | `gateway_api_enabled` |
| cert-manager | `v1.15.3` | kubespray 내장 | `cert_manager_enabled` |
| metrics-server | `v0.8.1` | kubespray 내장 | `metrics_server_enabled` |
| MetalLB | `v0.13.9` | kubespray 내장 | `metallb_enabled`, `metallb_config` |
| Argo CD | `v2.14.9` | 자체 role `roles/argocd` | `argocd_addon_*` |
| kubeconfig 병합 | - | 자체 role `roles/kubeconfig-merge` | `kubeconfig_merge_*` |

버전은 kubespray v2.31.0이 고정한 값입니다. 모두 `inventory/group_vars/all/onprem.yml` 한 파일에서 켜고 끕니다.

### 알아 둘 점

- **cert-manager는 Helm chart가 아니라 정적 매니페스트로 설치됩니다.**
  그래서 chart values(`installCRDs`, `config.*`, `prometheus.*`, `replicaCount`, `resources` 등)를
  쓸 수 없고, kubespray가 노출한 변수로만 조정합니다.

  | 03에서 쓰던 chart values | kubespray에서 대응 |
  | --- | --- |
  | `installCRDs: true` | 기본 동작. CRD 매니페스트를 별도로 apply합니다 |
  | `config.enableGatewayAPI: true` | `cert_manager_controller_extra_args: [--enable-gateway-api]` |
  | `prometheus.enabled: true` | 기본 동작. controller Pod에 `prometheus.io/scrape` 어노테이션이 이미 붙어 있습니다 |

  조정 가능한 변수는 `cert_manager_namespace`, `cert_manager_tolerations`,
  `cert_manager_nodeselector`, `cert_manager_affinity`, `cert_manager_dns_policy`,
  `cert_manager_dns_config`, `cert_manager_controller_extra_args`,
  `cert_manager_leader_election_namespace`, `cert_manager_trusted_internal_ca` 입니다.

  **조정할 수 없는 것**: replica 수(세 Deployment 모두 `replicas: 1` 하드코딩),
  Pod resource requests/limits(매니페스트에 아예 없음), PodDisruptionBudget,
  webhook/cainjector의 extra args(`extra_args` 는 controller에만 적용됩니다).
  홈랩 규모에서는 문제되지 않지만, HA가 필요해지면 이때 Helm으로 되돌리는 게 맞습니다.

- **Gateway API 지원은 스위치가 두 개입니다.** cert-manager 1.15 기준으로
  `ExperimentalGatewayAPISupport` 피처 게이트는 Beta로 승격되어 **이미 기본 `true`** 이고,
  `--enable-gateway-api` 플래그가 **기본 `false`** 입니다. 소스에서 두 조건을 `&&` 로 확인하므로
  피처 게이트만 켜면 아무 일도 일어나지 않습니다. 그래서 후자를 켭니다.

  ```yaml
  cert_manager_controller_extra_args:
    - --enable-gateway-api
  ```

  이 플래그를 켠 채로 Gateway API CRD가 없으면 controller가 기동에 실패합니다.
  kubespray는 `common_crds`(Gateway API)를 `ingress_controller/cert_manager` 보다 먼저 실행하므로
  한 번의 `cluster.yml` 안에서 순서는 안전합니다.

- **MetalLB 버전이 `0.13.9`입니다.** kubespray가 매니페스트를 통째로 템플릿으로 들고 있어서
  `metallb_version` 만 올리면 매니페스트와 어긋나 깨질 수 있습니다.
  `IPAddressPool` / `L2Advertisement` (`metallb.io/v1beta1`)는 그대로 지원되므로
  주소 풀 구성은 kubespray가 CR까지 만들어 줍니다.

  ```yaml
  metallb_config:
    address_pools:
      onprem-l2-pool:
        ip_range:
          - 192.168.0.230-192.168.0.255
        auto_assign: true
    layer2:
      - onprem-l2-pool
  ```

  `ip_range`는 **반드시 실제 노드 L2 네트워크에서 DHCP가 나눠 주지 않는 대역**이어야 합니다.

- **Argo CD는 kubespray 내장 add-on을 쓰지 않습니다.** (`argocd_enabled: false`)
  `server.insecure` 설정과 rollout 대기가 필요하고, EKS 쪽과 같은 절차를 쓰기 위해
  `02-bootstrap/roles/argocd` 를 별도 플레이북으로 실행합니다.

- `cert-manager` 와 `metallb-system` **네임스페이스는 kubespray 매니페스트가 직접 만듭니다.**
  그래서 `03-k8s-clusters/onprem/overlays/namespaces.yaml` 에서 빠졌습니다.

### 이미 GitOps로 설치해 둔 클러스터에서 옮길 때

`03-k8s-clusters`의 child `Application`에는 `resources-finalizer.argocd.argoproj.io` 가 없습니다.
그래서 root Application이 이들을 prune해도 **워크로드는 지워지지 않고 orphan 상태로 남습니다.**
서비스가 끊기지는 않지만, 옮기고 나면 kubespray가 그 위에 `kubectl apply` 를 하게 됩니다.

MetalLB는 GitOps로 `0.14.8`, kubespray는 `0.13.9`라 버전이 내려갑니다.
기존 리소스를 정리하고 새로 받는 편이 깔끔합니다.

```bash
# 1) Argo CD가 먼저 child Application을 정리하도록 root를 동기화
kubectl -n argocd get applications

# 2) orphan으로 남은 Helm 설치본 제거 (address pool CR은 kubespray가 다시 만듭니다)
kubectl delete namespace metallb-system
kubectl delete namespace cert-manager

# 3) kubespray add-on만 다시 적용
cd "${KUBESPRAY_DIR}"
ansible-playbook -i <인벤토리> --become playbooks/cluster.yml \
  --tags gateway_api,cert-manager,metrics_server,metallb
```

`cert-manager` 네임스페이스를 지우면 `ClusterIssuer` 가 참조하는
`route53-credentials-secret` 도 함께 지워집니다. External Secrets Operator가 다시 만들어 주므로
Vault가 정상이면 몇 분 안에 회복됩니다.

MetalLB를 다시 설치하면 LoadBalancer Service에 붙어 있던 IP가 재할당됩니다.
같은 주소 풀을 쓰므로 대역은 같지만, Gateway IP가 바뀔 수 있으니 내부 DNS 레코드를 확인하세요.

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
| kube-proxy strictARP | 활성화 | MetalLB L2 모드 요구사항 |

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
  - 192.168.0.77
upstream_dns_servers:              # CoreDNS/NodeLocal DNS가 외부 도메인을 물어볼 대상
  - 192.168.0.77
```

결과적으로 모든 노드의 `/etc/resolv.conf` 가 아래로 고정됩니다.

```
nameserver 169.254.25.10   # NodeLocal DNS
nameserver 192.168.0.77    # 내부 DNS
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
2. kubespray `playbooks/cluster.yml` — 클러스터 설치 + 내장 add-on
   (Gateway API CRD, cert-manager, metrics-server, MetalLB)
3. `onprem-install-addons.yml` — Argo CD 설치, `~/.kube/config` 병합

단계별로 따로 실행하려면 아래처럼 하면 됩니다.

```bash
# 1) 사전 준비
ANSIBLE_CONFIG=./onprem/ansible.cfg ansible-playbook \
  -i onprem/inventory/hosts.yml onprem-prepare-nodes.yml

# 2) 클러스터 + 내장 add-on 설치 (kubespray 디렉터리에서, kubespray의 ansible.cfg로)
source ./scripts/kubespray.env
source "${KUBESPRAY_VENV}/bin/activate"
cd "${KUBESPRAY_DIR}"
ansible-playbook -i <저장소경로>/02-bootstrap/onprem/inventory/hosts.yml --become playbooks/cluster.yml

# 3) 자체 add-on
ANSIBLE_CONFIG=./onprem/ansible.cfg ansible-playbook \
  -i onprem/inventory/hosts.yml onprem-install-addons.yml
```

kubespray 내장 add-on만 다시 적용하려면 태그를 씁니다. 클러스터 전체를 다시 돌 필요가 없습니다.

```bash
cd "${KUBESPRAY_DIR}"
ansible-playbook -i <인벤토리> --become playbooks/cluster.yml \
  --tags gateway_api,cert-manager,metrics_server,metallb
```

자체 add-on도 태그가 있습니다. (`argocd`, `kubeconfig`)

```bash
./scripts/onprem-bootstrap.sh --tags argocd
```

## kubeconfig

`kubeconfig_localhost: true` 로 설정되어 있어, 설치가 끝나면 아래 경로에 kubeconfig가 생깁니다.

```
02-bootstrap/onprem/inventory/artifacts/admin.conf
```

`kubeconfig_localhost_ansible_host: true` 이므로 server 주소가 control plane의
`ansible_host` 로 들어가 있어 그대로 쓸 수 있습니다.

3단계의 `kubeconfig-merge` role이 이 파일을 **Ansible 실행 호스트의 `~/.kube/config` 에
자동으로 병합**하므로 보통은 따로 할 일이 없습니다.

```bash
kubectl config get-contexts
kubectl --context onprem-admin get nodes
```

- 컨텍스트 이름은 `kubeconfig_merge_context_name` (기본값 `onprem-admin`)입니다.
  kubespray 원본 이름(`kubernetes-admin@cluster.local`)은 다른 클러스터와 구분되지 않아 바꿔서 넣습니다.
- 기존 컨텍스트는 지워지지 않고, 병합 전 `~/.kube/config` 는 `.bak` 파일로 백업됩니다.
- 병합 결과는 `--flatten` 된 단일 파일이라 인증서 경로 참조 없이 그대로 쓸 수 있습니다.
- 실행 호스트에 `kubectl` 이 없으면 이 단계는 경고만 남기고 건너뜁니다.

자동 설정을 원하지 않으면 오버라이드 파일에서 끄고 산출물을 직접 쓰면 됩니다.

```yaml
kubeconfig_merge_enabled: false
```

```bash
export KUBECONFIG=$PWD/onprem/inventory/artifacts/admin.conf
kubectl get nodes
```

> `inventory/artifacts/` 와 `inventory/credentials/` 는 kubespray가 만드는 로컬 산출물이며
> 자격증명이 들어 있어 `.gitignore` 처리되어 있습니다.

## add-on 설치 확인

```bash
kubectl get crd | grep gateway.networking.k8s.io
kubectl -n cert-manager get pods
kubectl top nodes
kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspool,l2advertisement
kubectl -n argocd get pods
```

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
