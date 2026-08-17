#!/usr/bin/env bash
# kubespray reset 플레이북으로 온프렘 노드를 클러스터 설치 이전 상태로 되돌립니다.
#
# 주의: 클러스터와 노드의 Kubernetes 관련 상태를 모두 삭제합니다.
#       VM 자체는 남으므로, VM까지 지우려면 01-infra/onprem 에서 terraform destroy 하세요.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=./kubespray.env
source "${SCRIPT_DIR}/kubespray.env"

INVENTORY="${BOOTSTRAP_DIR}/onprem/inventory/hosts.yml"

if [ ! -d "${KUBESPRAY_DIR}/.git" ]; then
  echo "kubespray가 없습니다. 먼저 ./scripts/fetch-kubespray.sh 를 실행하세요." >&2
  exit 1
fi

if [ -f "${KUBESPRAY_VENV}/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "${KUBESPRAY_VENV}/bin/activate"
fi

echo "==> kubespray reset (${KUBESPRAY_VERSION})"
(
  cd "${KUBESPRAY_DIR}"
  ANSIBLE_CONFIG="${KUBESPRAY_DIR}/ansible.cfg" ansible-playbook \
    -i "${INVENTORY}" \
    --become \
    playbooks/reset.yml "$@"
)
