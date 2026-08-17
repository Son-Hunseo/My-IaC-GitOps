#!/usr/bin/env bash
# AWS EKS 부트스트랩 실행 스크립트입니다.
#
# EKS는 관리형 control plane이므로 클러스터 설치(kubespray) 단계가 없고,
# 온프렘과 같은 roles/argocd 역할로 Argo CD add-on만 설치합니다.
#
# 사전 준비:
#   aws eks update-kubeconfig --region <region> --name <cluster-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"

echo "==> Argo CD add-on 설치 (AWS EKS)"
ANSIBLE_CONFIG="${BOOTSTRAP_DIR}/aws/ansible.cfg" ansible-playbook \
  -i "${BOOTSTRAP_DIR}/aws/inventory/eks.yml" \
  "${BOOTSTRAP_DIR}/aws-install-argocd.yml" "$@"

echo "==> 완료"
echo "    Argo CD 초기 비밀번호:"
echo "      kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
