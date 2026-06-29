# Prepare

이 문서는 개발/운영 PC에서 인프라 도구를 준비하기 위한 가이드입니다.

## 0. 환경 명시

권장 환경은 다음 중 하나입니다.

- macOS
- Linux(Ubuntu)

## 1. AWS CLI 설치법

### macOS

AWS 공식 설치 패키지를 사용합니다.

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
```

Homebrew를 사용할 수도 있습니다.

```bash
brew install awscli
aws --version
```

### Linux(Ubuntu)

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

ARM64 환경이면 다운로드 URL을 다음으로 바꿉니다.

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
```

### AWS 인증 설정

```bash
aws configure
```

## 2. Terraform 설치법

### macOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

### Linux(Ubuntu)

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform
terraform version
```

### 동작 확인

```bash
terraform -help
terraform version
```

## 3. Ansible 설치법

Ansible은 Python 기반 도구이므로 `pipx` 설치를 권장합니다. `pipx`를 사용하면 Ansible 실행 환경을 시스템 Python과 분리할 수 있습니다.

### macOS

```bash
brew install pipx
pipx ensurepath
pipx install --include-deps ansible
ansible --version
ansible-playbook --version
```

셸을 다시 열거나 다음 명령으로 PATH를 갱신합니다.

```bash
source ~/.zshrc
```

### Linux(Ubuntu)

```bash
sudo apt update
sudo apt install -y pipx python3-venv
pipx ensurepath
pipx install --include-deps ansible
ansible --version
ansible-playbook --version
```

셸을 다시 열거나 다음 명령으로 PATH를 갱신합니다.

```bash
source ~/.bashrc
```

## 4. kubectl 설치법

### macOS

```bash
brew install kubectl
kubectl version --client
```

### Linux(Ubuntu)

Kubernetes 공식 APT 저장소를 사용합니다.

```bash
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubectl
kubectl version --client
```

클러스터 버전에 맞춰 `v1.34` 부분을 변경할 수 있습니다. 예를 들어 클러스터가 Kubernetes 1.33이면 `core:/stable:/v1.33`을 사용합니다.

## 5. Helm 설치법

### macOS

```bash
brew install helm
helm version
```

### Linux(Ubuntu)

Helm 공식 설치 스크립트를 사용합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

APT 저장소로 설치할 수도 있습니다.

```bash
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install -y helm
helm version
```

### Helm 동작 확인

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/nginx
```

## 참고 공식 문서

- AWS CLI 설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Terraform 설치: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
- Ansible 설치: https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html
- kubectl 설치: https://kubernetes.io/docs/tasks/tools/
- EKS kubeconfig: https://docs.aws.amazon.com/cli/latest/reference/eks/update-kubeconfig.html
- Helm 설치: https://helm.sh/docs/intro/install/
