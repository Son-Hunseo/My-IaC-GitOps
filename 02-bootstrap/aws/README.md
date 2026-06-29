# AWS EKS Bootstrap

이 디렉터리는 `01-infra/aws` 단계에서 이미 생성된 AWS EKS 클러스터에 Argo CD를 설치하는 Ansible 실행 단위입니다.
노드 준비, kubeadm, Calico 설치는 실행하지 않습니다.

## 구성

- `ansible.cfg`: AWS EKS bootstrap용 Ansible 기본 설정입니다.
- `inventory/eks.yml`: 기존 EKS 클러스터에 GitOps 도구를 설치할 로컬 실행 인벤토리입니다.
- `inventory/group_vars/all.yml`: Argo CD 설치 변수입니다.
- `playbooks/install-argocd.yml`: EKS 클러스터에 Argo CD를 설치합니다.
- `roles/argocd/`: AWS EKS용 Argo CD 설치 역할입니다.

## 사전 준비

1. 자동화 호스트에서 `kubectl`이 EKS API 서버에 접속할 수 있어야 합니다.
2. `KUBECONFIG` 환경 변수 또는 `inventory/eks.yml`의 `argocd_kubeconfig` 값을 EKS kubeconfig 경로로 설정해야 합니다.
3. kubeconfig에 여러 컨텍스트가 있으면 `argocd_kube_context`를 EKS 컨텍스트 이름으로 지정해야 합니다.

## 실행

프로젝트 루트의 `02-bootstrap` 디렉터리에서 실행합니다.

```bash
ANSIBLE_CONFIG=./aws/ansible.cfg ansible-playbook aws/playbooks/install-argocd.yml
```

## 주요 변수

- `argocd_version`: 설치할 Argo CD manifest 버전입니다.
- `argocd_namespace`: Argo CD를 설치할 네임스페이스입니다.
- `argocd_server_insecure`: 테스트용 HTTP Gateway 뒤에서 Argo CD HTTPS 리다이렉트를 끌지 여부입니다.
- `argocd_kubeconfig`: EKS 클러스터에 접속할 kubeconfig 경로입니다.
- `argocd_kube_context`: 사용할 EKS kubeconfig 컨텍스트입니다.

## Argo CD 초기 비밀번호 확인

초기 로그인 계정은 `admin`이며, 초기 비밀번호는 아래 명령으로 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
