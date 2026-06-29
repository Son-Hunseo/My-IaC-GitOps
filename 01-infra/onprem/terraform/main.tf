locals {
  # 한국어 주석: 템플릿과 cloud-init datastore는 별도 값이 없으면 기본 Proxmox 노드/디스크 datastore를 재사용합니다.
  template_node_name        = coalesce(var.vm_template_node_name, var.proxmox_node_name)
  cloud_init_datastore_id   = coalesce(var.cloud_init_datastore_id, var.datastore_id)
  ordered_vm_node_names     = sort(keys(var.vm_nodes))
  ordered_vm_node_positions = { for index, name in local.ordered_vm_node_names : name => index }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.vm_nodes

  # 한국어 주석: VM 이름은 prefix와 map key를 조합해 역할과 번호가 드러나도록 유지합니다.
  name        = "${var.vm_name_prefix}-${each.key}"
  description = var.vm_description
  node_name   = var.proxmox_node_name
  vm_id       = coalesce(each.value.vm_id, var.vm_id_start + local.ordered_vm_node_positions[each.key])

  # 한국어 주석: Kubernetes 설치는 이 계층의 책임이 아니므로 VM clone과 cloud-init 기반 OS 초기 설정까지만 수행합니다.
  clone {
    vm_id     = var.vm_template_id
    node_name = local.template_node_name
    full      = true
  }

  # 한국어 주석: QEMU guest agent는 IP 조회와 운영 가시성을 위해 활성화합니다. 템플릿 내부에도 agent가 설치되어 있어야 합니다.
  agent {
    enabled = true
  }

  # 한국어 주석: Linux 계열 cloud image를 전제로 하며, 실제 OS 이미지는 Proxmox 템플릿에서 관리합니다.
  operating_system {
    type = "l26"
  }

  # 한국어 주석: master는 4 vCPU, worker는 2 vCPU를 기본 정의로 사용하되 vm_nodes에서 명시적으로 조정할 수 있습니다.
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  # 한국어 주석: master는 8 GB, worker는 4 GB를 기본 정의로 사용합니다.
  memory {
    dedicated = each.value.memory_mb
  }

  # 한국어 주석: 모든 Kubernetes 노드 VM은 기본 128 GB 디스크를 사용합니다.
  disk {
    datastore_id = var.datastore_id
    interface    = var.disk_interface
    size         = each.value.disk_gb
    file_format  = var.disk_file_format
  }

  # 한국어 주석: MetalLB 구성은 Kubernetes 계층에서 처리하므로 여기서는 VM NIC와 L2/L3 주소만 준비합니다.
  network_device {
    bridge  = var.network_bridge
    model   = var.network_model
    vlan_id = var.network_vlan_id
  }

  initialization {
    # 한국어 주석: cloud-init 설정은 VM 생성 직후 SSH 접근과 고정 IP 설정에 필요한 최소 범위만 포함합니다.
    datastore_id = local.cloud_init_datastore_id

    user_account {
      username = var.cloud_init_username
      keys     = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = var.gateway_ipv4
      }
    }

    dns {
      servers = var.dns_servers
    }
  }

  lifecycle {
    # 한국어 주석: 운영 중 Proxmox 콘솔에서 VM을 시작/중지할 수 있으므로 running 상태 변경은 Terraform drift로 다루지 않습니다.
    ignore_changes = [
      started,
    ]
  }
}

