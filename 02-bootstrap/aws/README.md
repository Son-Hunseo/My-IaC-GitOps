# AWS EKS Bootstrap

`01-infra/aws` 단계에서 이미 생성된 AWS EKS 클러스터에 Argo CD add-on을 설치하는 실행 단위입니다.

EKS는 관리형 control plane이므로 **클러스터 설치(kubespray) 단계가 없습니다.**
온프렘과 동일한 `02-bootstrap/roles/argocd` 역할을 그대로 사용하고, 실행 위치만 로컬입니다.

## 구성

- `ansible.cfg`: AWS EKS bootstrap용 Ansible 설정입니다.
- `inventory/eks.yml`: 로컬 실행 인벤토리입니다.
- `inventory/group_vars/all/aws.yml`: **이 환경에서 바꾸는 모든 변수를 담은 단 하나의 파일입니다.**

플레이북과 role은 온프렘과 공유합니다.

- `02-bootstrap/aws-install-argocd.yml`
- `02-bootstrap/roles/argocd/`

## 사전 준비

1. 자동화 호스트에서 `kubectl`이 EKS API 서버에 접속할 수 있어야 합니다.

   ```bash
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```

2. `KUBECONFIG` 환경 변수 또는 `inventory/group_vars/all/aws.yml` 의 `argocd_addon_kubeconfig` 값을
   EKS kubeconfig 경로로 설정해야 합니다.
3. kubeconfig에 여러 컨텍스트가 있으면 `argocd_addon_kube_context` 를 EKS 컨텍스트 이름으로 지정해야 합니다.

## 실행

`02-bootstrap` 디렉터리에서 실행합니다.

```bash
./scripts/aws-bootstrap.sh
```

스크립트 없이 직접 실행하려면:

```bash
ANSIBLE_CONFIG=./aws/ansible.cfg ansible-playbook \
  -i aws/inventory/eks.yml aws-install-argocd.yml
```

## 주요 변수

모두 `inventory/group_vars/all/aws.yml` 한 파일에서 관리합니다.

- `argocd_addon_version`: 설치할 Argo CD manifest 버전입니다.
- `argocd_addon_namespace`: Argo CD를 설치할 네임스페이스입니다.
- `argocd_addon_server_insecure`: 테스트용 HTTP Gateway 뒤에서 Argo CD HTTPS 리다이렉트를 끌지 여부입니다.
- `argocd_addon_kubeconfig`: EKS 클러스터에 접속할 kubeconfig 경로입니다.
- `argocd_addon_kube_context`: 사용할 EKS kubeconfig 컨텍스트입니다.

## Argo CD 초기 비밀번호 확인

초기 로그인 계정은 `admin`이며, 초기 비밀번호는 아래 명령으로 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
