#!/usr/bin/env bash
# AWS EKS 부트스트랩 실행 스크립트입니다.
#
# EKS는 관리형 control plane이므로 클러스터 설치(kubespray) 단계가 없고,
# kubespray 내장 add-on도 쓸 수 없습니다. (add-on role이 control plane 노드에
# SSH해서 kubectl을 실행하는 구조라 EKS에는 해당 노드가 없습니다)
#
# 그래서 온프렘이 kubespray로 얻는 것들을 02-bootstrap/roles/ 의 자체 role로 설치합니다.
#
#   - kubeconfig 등록  : aws eks update-kubeconfig
#   - Gateway API CRD
#   - metrics-server
#   - Argo CD
#
# AWS EBS CSI Driver는 IRSA role ARN이 필요한 EKS 관리형 add-on이라
# 01-infra/aws 의 terraform이 IAM role과 함께 설치합니다.
#
# 사전 준비:
#   aws/inventory/group_vars/all/aws.yml 의 eks_cluster_name, eks_region 설정
#   (AWS 자격증명은 aws CLI가 평소 쓰는 방식 그대로 사용합니다)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"

echo "==> 02-bootstrap add-on 설치 (AWS EKS)"
ANSIBLE_CONFIG="${BOOTSTRAP_DIR}/aws/ansible.cfg" ansible-playbook \
  -i "${BOOTSTRAP_DIR}/aws/inventory/eks.yml" \
  "${BOOTSTRAP_DIR}/aws-install-addons.yml" "$@"

echo "==> 완료"
echo "    Argo CD 초기 비밀번호:"
echo "      kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
