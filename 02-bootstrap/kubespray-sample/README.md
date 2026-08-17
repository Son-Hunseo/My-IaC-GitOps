# kubespray sample inventory (참조 전용)

이 디렉터리는 kubespray **v2.31.0**의 `inventory/sample/` 을 그대로 복사한 것입니다.
수정하지 마세요. 그리고 **여기 있는 값은 클러스터에 적용되지 않습니다.**

## 왜 복사해 두나요

kubespray의 모든 기본값은 `roles/kubespray_defaults/defaults/main/` 에 있고,
`inventory/sample/group_vars/` 는 "바꿀 수 있는 값들을 주석과 함께 나열한 문서"에 가깝습니다.

sample 계층을 그대로 인벤토리에 복사해서 파일마다 값을 고치면

- 어떤 값을 왜 바꿨는지 27개 파일에 흩어지고
- kubespray 버전을 올릴 때 업스트림과의 diff를 알아보기 어려워집니다.

그래서 이 저장소는 **sample을 참조용으로만 복사해 두고, 실제로 바꾸는 값은
환경별 오버라이드 파일 하나에만** 선언합니다.

| 환경 | 실제로 적용되는 단 하나의 파일 |
| --- | --- |
| On-Premise | `02-bootstrap/onprem/inventory/group_vars/all/onprem.yml` |
| AWS EKS | `02-bootstrap/aws/inventory/group_vars/all/aws.yml` |

인벤토리 `group_vars` 는 role의 `defaults` 보다 우선순위가 높으므로,
오버라이드 파일에 선언한 값이 kubespray 기본값을 항상 이깁니다.

## 사용법

"이 값을 바꿀 수 있나?" 를 확인할 때 이 디렉터리에서 변수 이름을 찾고,
바꾸기로 했다면 위 표의 오버라이드 파일에 주석과 함께 추가하세요.

```bash
grep -rn "kube_proxy_mode" 02-bootstrap/kubespray-sample/
```

## 버전을 올릴 때

1. `02-bootstrap/scripts/kubespray.env` 의 `KUBESPRAY_VERSION` 을 수정합니다.
2. `./scripts/fetch-kubespray.sh` 로 새 태그를 내려받습니다.
3. 새 태그의 `inventory/sample/` 로 이 디렉터리를 다시 덮어씁니다.

   ```bash
   source 02-bootstrap/scripts/kubespray.env
   rm -rf 02-bootstrap/kubespray-sample/group_vars
   cp -r "${KUBESPRAY_DIR}/inventory/sample/group_vars" 02-bootstrap/kubespray-sample/
   cp "${KUBESPRAY_DIR}/inventory/sample/inventory.ini" 02-bootstrap/kubespray-sample/
   ```

4. `git diff` 로 업스트림에서 바뀐 변수를 확인하고, 필요한 것만 오버라이드 파일에 반영합니다.
