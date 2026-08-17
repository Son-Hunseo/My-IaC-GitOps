#!/usr/bin/env bash
# 고정된 태그의 kubespray를 내려받고, kubespray 전용 Ansible virtualenv를 준비합니다.
# 이미 준비되어 있으면 아무것도 바꾸지 않습니다. (재실행 가능)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kubespray.env
source "${SCRIPT_DIR}/kubespray.env"

echo "==> kubespray ${KUBESPRAY_VERSION}"
echo "    clone dir : ${KUBESPRAY_DIR}"
echo "    venv dir  : ${KUBESPRAY_VENV}"

if [ ! -d "${KUBESPRAY_DIR}/.git" ]; then
  echo "==> kubespray ${KUBESPRAY_VERSION} 를 클론합니다."
  mkdir -p "$(dirname "${KUBESPRAY_DIR}")"
  git clone --depth 1 --branch "${KUBESPRAY_VERSION}" "${KUBESPRAY_REPO}" "${KUBESPRAY_DIR}"
else
  current="$(git -C "${KUBESPRAY_DIR}" describe --tags --exact-match 2>/dev/null || echo unknown)"
  if [ "${current}" != "${KUBESPRAY_VERSION}" ]; then
    echo "==> 이미 있는 클론의 태그가 ${current} 입니다. ${KUBESPRAY_VERSION} 로 맞춥니다."
    git -C "${KUBESPRAY_DIR}" fetch --depth 1 origin "refs/tags/${KUBESPRAY_VERSION}:refs/tags/${KUBESPRAY_VERSION}"
    git -C "${KUBESPRAY_DIR}" checkout -f "tags/${KUBESPRAY_VERSION}"
  else
    echo "==> 이미 ${KUBESPRAY_VERSION} 로 체크아웃되어 있습니다."
  fi
fi

if [ ! -x "${KUBESPRAY_VENV}/bin/ansible-playbook" ]; then
  echo "==> kubespray 전용 virtualenv를 만듭니다."
  python3 -m venv "${KUBESPRAY_VENV}"
  "${KUBESPRAY_VENV}/bin/pip" install --upgrade pip
  "${KUBESPRAY_VENV}/bin/pip" install -r "${KUBESPRAY_DIR}/requirements.txt"
else
  echo "==> virtualenv가 이미 준비되어 있습니다."
fi

echo "==> 완료"
"${KUBESPRAY_VENV}/bin/ansible" --version | head -n 1
