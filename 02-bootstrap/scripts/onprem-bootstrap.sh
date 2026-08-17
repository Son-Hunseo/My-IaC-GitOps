#!/usr/bin/env bash
# 온프렘(Proxmox) 부트스트랩 전체 실행 스크립트입니다.
#
#   1) 노드 사전 준비    : 02-bootstrap 자체 플레이북 (디스크 확장, 추가 패키지)
#   2) 클러스터 + add-on : kubespray playbooks/cluster.yml
#                          (Gateway API CRD, cert-manager, metrics-server, MetalLB 포함)
#   3) 자체 add-on       : 02-bootstrap 자체 플레이북 (Argo CD, kubeconfig 병합)
#
# 1/3단계와 2단계는 ansible.cfg가 서로 달라야 하므로(각각 02-bootstrap용,
# kubespray용) 이 스크립트가 나눠서 실행합니다.
#
# 사용법:
#   ./scripts/onprem-bootstrap.sh              # 전체 실행
#   ./scripts/onprem-bootstrap.sh --limit ...  # 추가 인자는 세 단계 모두에 전달됩니다
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=./kubespray.env
source "${SCRIPT_DIR}/kubespray.env"

INVENTORY="${BOOTSTRAP_DIR}/onprem/inventory/hosts.yml"
ONPREM_CFG="${BOOTSTRAP_DIR}/onprem/ansible.cfg"

if [ ! -d "${KUBESPRAY_DIR}/.git" ]; then
  echo "kubespray가 없습니다. 먼저 ./scripts/fetch-kubespray.sh 를 실행하세요." >&2
  exit 1
fi

if [ -f "${KUBESPRAY_VENV}/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "${KUBESPRAY_VENV}/bin/activate"
fi

echo "==> 1/3 노드 사전 준비 (디스크 확장, 추가 패키지)"
ANSIBLE_CONFIG="${ONPREM_CFG}" ansible-playbook \
  -i "${INVENTORY}" \
  "${BOOTSTRAP_DIR}/onprem-prepare-nodes.yml" "$@"

echo "==> 2/3 kubespray 클러스터 + 내장 add-on 설치 (${KUBESPRAY_VERSION})"
(
  cd "${KUBESPRAY_DIR}"
  ANSIBLE_CONFIG="${KUBESPRAY_DIR}/ansible.cfg" ansible-playbook \
    -i "${INVENTORY}" \
    --become \
    playbooks/cluster.yml "$@"
)

echo "==> 3/3 02-bootstrap 자체 add-on 설치 (Argo CD, kubeconfig 병합)"
ANSIBLE_CONFIG="${ONPREM_CFG}" ansible-playbook \
  -i "${INVENTORY}" \
  "${BOOTSTRAP_DIR}/onprem-install-addons.yml" "$@"

echo "==> 완료"
echo "    kubeconfig : ${BOOTSTRAP_DIR}/onprem/inventory/artifacts/admin.conf"
echo "                 (~/.kube/config 에 'onprem-admin' 컨텍스트로 병합됨)"
echo "    Argo CD 초기 비밀번호:"
echo "      kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
