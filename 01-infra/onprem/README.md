# Proxmox VM Infrastructure

이 실행 단위는 Proxmox VE 위에 Kubernetes 노드로 사용할 VM 3대를 생성합니다.

- master 1대: 4 vCPU, 8 GB memory, 128 GB disk
- worker 2대: 각 4 vCPU, 8 GB memory, 128 GB disk

이 Terraform 실행 단위는 VM 프로비저닝까지만 담당합니다. Kubernetes 설치, kubeadm 부트스트랩, CNI, MetalLB, GitOps 컨트롤러, 애플리케이션 배포는 포함하지 않습니다.

## 전제 조건

1. Terraform 1.6 이상
2. Proxmox VE API 접근 권한
3. VM clone에 사용할 Proxmox template
4. template 내부의 cloud-init 지원
5. SSH 접속에 사용할 공개키
6. VM이 사용할 network bridge, datastore, gateway, DNS 정보

## 사전 준비

### Proxmox template

Terraform이 VM을 복제할 원본 VM template을 먼저 준비합니다. 일반 VM을 만들고 필요한 패키지와 Proxmox 설정을 넣은 뒤 template으로 변환하면 됩니다.

기본 흐름은 다음과 같습니다.

1. Proxmox에서 일반 VM을 생성하고 Linux OS를 설치합니다.
2. VM 내부에 `cloud-init`과 `qemu-guest-agent`를 설치합니다.
3. `qemu-guest-agent` 서비스를 활성화합니다.
4. cloud-init이 clone된 VM에서 다시 초기화되도록 VM 내부 상태를 정리합니다.
5. VM을 종료합니다.
6. Proxmox VM 설정(Hardware)에서 Cloud-Init drive를 Add합니다.
7. Proxmox VM 설정(Options)에서 QEMU Guest Agent 옵션을 활성화합니다.
8. Proxmox UI에서 VM을 우클릭한 뒤 `Convert to template`을 실행합니다.

Ubuntu/Debian 계열 VM 내부에서는 보통 다음 정도만 설치하면 됩니다.

```bash
sudo apt update
sudo apt install -y cloud-init qemu-guest-agent
sudo systemctl enable qemu-guest-agent
sudo cloud-init clean
```

Cloud-Init drive는 Terraform이 지정한 IP, gateway, DNS, SSH key 같은 seed 데이터를 Proxmox에서 VM으로 전달하는 장치입니다. VM 내부에 `cloud-init`을 설치하고 `cloud-init clean`을 실행했더라도 Cloud-Init drive 단계는 유지해야 합니다.

`terraform.tfvars`에는 template VM ID를 `vm_template_id`에 입력합니다. template이 VM을 생성할 node와 다른 node에 있으면 `vm_template_node_name`도 함께 지정합니다.

### Proxmox API token

Proxmox UI에서 `Datacenter > Permissions > API Tokens`로 이동해 Terraform용 token을 생성합니다.
`Datacenter > Permissions > Add` 에서 API Token Permission으로 토큰에 필요한(VM clone/create/update/delete, datastore 사용, network 사용) 권한을 부여한다.

`terraform.tfvars`에는 token ID와 secret을 분리해서 입력합니다.

```hcl
proxmox_api_token_id     = "terraform@pve!gitops"
proxmox_api_token_secret = "REPLACE_WITH_SECRET"
```

API token secret은 생성 시 한 번만 표시되므로 안전한 secret store에 보관하고 저장소에는 커밋하지 마십시오.

### SSH public keys

VM에 SSH로 접속할 관리자의 공개키를 준비합니다. 로컬 PC에 키가 없다면 다음처럼 생성할 수 있습니다.

```bash
ssh-keygen -t ed25519 -C "admin@example"
```

Terraform에는 개인키가 아니라 `.pub` 공개키 한 줄 전체를 입력합니다.

```bash
cat ~/.ssh/id_ed25519.pub
```

확인한 공개키를 `terraform.tfvars`에 넣습니다.

```hcl
ssh_public_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... admin@example",
]
```

## 주요 변수

| 변수 | 설명 |
| --- | --- |
| `proxmox_endpoint` | Proxmox VE API endpoint |
| `proxmox_api_token_id` | Proxmox API token ID |
| `proxmox_api_token_secret` | Proxmox API token secret |
| `proxmox_node_name` | VM을 생성할 Proxmox node |
| `vm_template_id` | clone 원본 VM template ID |
| `datastore_id` | VM disk datastore |
| `network_bridge` | VM NIC가 연결될 bridge |
| `gateway_ipv4` | VM 기본 gateway |
| `ssh_public_keys` | cloud-init user에 주입할 SSH public key |
| `vm_nodes` | master/worker별 IP, CPU, memory, disk 정의 |

## 예시 설정

아래 Terraform 명령은 이 README가 있는 `01-infra/onprem` 기준으로 `terraform` 디렉터리에서 실행합니다.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`에 실제 환경 값을 입력합니다. 이 파일에는 실제 API token secret 또는 개인키를 커밋하지 마십시오.

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

예상되는 변경 사항이 master 1대와 worker 2대 VM 생성인지 확인합니다.

## 적용

```bash
terraform apply
```

적용 후 생성된 VM 정보는 다음 명령으로 확인합니다.

```bash
terraform output
terraform output vm_nodes
```

## 삭제

```bash
terraform destroy
```

이 명령은 Terraform state가 관리하는 Proxmox VM을 삭제합니다. Kubernetes나 애플리케이션 state가 VM 내부에 있을 경우 함께 사라질 수 있으므로, 실제 운영 환경에서는 백업과 데이터 보존 정책을 먼저 확인해야 합니다.

## Notes and limitations

- 이 실행 단위는 MetalLB를 설치하거나 구성하지 않습니다.
- 이 실행 단위는 Kubernetes control plane 또는 worker join 절차를 수행하지 않습니다.
- VM template 생성은 별도 작업입니다.
- `proxmox_insecure = true`는 자체 서명 인증서 환경에서만 임시로 사용하고, 가능하면 신뢰 가능한 TLS 인증서를 구성하십시오.
- IP 주소는 `vm_nodes`에서 CIDR 형식으로 명시합니다.
