# On-Premise Kubernetes Bootstrap

이 디렉터리는 Proxmox에서 생성된 VM을 Kubernetes 클러스터 노드로 초기화하고, Calico와 Argo CD까지 설치하는 Ansible 실행 단위입니다.

## 구성

- `ansible.cfg`: On-Premise bootstrap용 Ansible 기본 설정입니다.
- `inventory/hosts.yml`: Proxmox VM 인벤토리 예시입니다.
- `inventory/group_vars/`: 클러스터 공통 변수와 Kubernetes 변수를 관리합니다.
- `playbooks/`: 단계별 Kubernetes bootstrap 플레이북과 전체 실행 플레이북입니다.
- `roles/`: 디스크 확장, 시스템 사전 준비, containerd, kubeadm 설치, control plane 초기화, worker join, Calico, Argo CD 역할입니다.

## 사전 준비

1. Ansible 실행 호스트에서 대상 VM에 SSH 접속이 가능해야 합니다.
2. 대상 VM 사용자는 `sudo` 권한을 가져야 합니다.
3. `inventory/hosts.yml`의 IP, 사용자, 호스트명을 실제 VM 값으로 수정해야 합니다.
4. control plane 노드와 worker 노드는 같은 L2/L3 네트워크에서 Kubernetes API 서버에 접근 가능해야 합니다.

윈도우 기반 환경에서 실행하는 경우 WSL 안에서 사전 준비를 하고 실행합니다.

## Ansible 접속 확인

`02-bootstrap` 디렉터리에서 실행합니다.

```bash
ansible -i onprem/inventory/hosts.yml all -m ping
ansible -i onprem/inventory/hosts.yml all -m command -a "whoami" --become
```

두 번째 명령의 결과가 각 VM에서 `root`로 나오면 Ansible의 sudo 권한 상승까지 정상입니다.

## 실행

```bash
ANSIBLE_CONFIG=./onprem/ansible.cfg ansible-playbook onprem/playbooks/site.yml
```

## 온프렘 마스터 노드에서 kubeconfig 가져오는 법

### 명령어

```bash
ssh user@master-ip 'sudo cat /etc/kubernetes/admin.conf' > "$HOME/.kube/admin.tmp"
TMP="KUBECONFIG=$HOME/.kube/admin.tmp"

SERVER=$(env $TMP kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(env $TMP kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CLIENT_CERT=$(env $TMP kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
CLIENT_KEY=$(env $TMP kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')

kubectl config set-cluster test-cluster --server="$SERVER"
kubectl config set clusters.test-cluster.certificate-authority-data "$CA_DATA" --set-raw-bytes=false

kubectl config set-credentials test-admin
kubectl config set users.test-admin.client-certificate-data "$CLIENT_CERT" --set-raw-bytes=false
kubectl config set users.test-admin.client-key-data "$CLIENT_KEY" --set-raw-bytes=false

kubectl config set-context test --cluster=test-cluster --user=test-admin
kubectl config use-context test
rm "$HOME/.kube/admin.tmp"
```

### 확인

```bash
kubectl config get-contexts
kubectl config view --minify
kubectl get nodes
```

마스터 노드에서 로컬 PC로 kubeconfig를 가져와서 기존 kubeconfig와 병합합니다. (config 없을 경우 생성)

## Argo 초기 계정 확인

초기 로그인 계정은 `admin`이며, 초기 비밀번호는 아래 명령으로 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 멱등성 보장

플레이북은 재실행을 전제로 작성되어 있습니다.
이미 초기화된 control plane은 다시 `kubeadm init`을 실행하지 않으며, 이미 join된 worker는 다시 join하지 않습니다.
Argo CD 설치 단계도 같은 버전과 같은 manifest를 다시 적용할 수 있도록 작성되어 있습니다.
