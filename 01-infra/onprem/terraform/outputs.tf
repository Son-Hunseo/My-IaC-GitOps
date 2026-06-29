output "vm_nodes" {
  # 한국어 주석: 후속 Kubernetes bootstrap 단계에서 참조할 수 있는 VM 식별 정보와 주소 정보를 제공합니다.
  description = "Provisioned Proxmox VM summary."
  value = {
    for name, vm in proxmox_virtual_environment_vm.node : name => {
      vm_id      = vm.vm_id
      name       = vm.name
      role       = var.vm_nodes[name].role
      ip_address = var.vm_nodes[name].ip_address
      cores      = var.vm_nodes[name].cores
      memory_mb  = var.vm_nodes[name].memory_mb
      disk_gb    = var.vm_nodes[name].disk_gb
    }
  }
}

output "master_node_names" {
  # 한국어 주석: master 역할 VM만 빠르게 확인하기 위한 출력입니다.
  description = "Names of VMs marked as master nodes."
  value       = [for name, node in var.vm_nodes : "${var.vm_name_prefix}-${name}" if node.role == "master"]
}

output "worker_node_names" {
  # 한국어 주석: worker 역할 VM 목록을 후속 자동화에서 사용할 수 있도록 제공합니다.
  description = "Names of VMs marked as worker nodes."
  value       = [for name, node in var.vm_nodes : "${var.vm_name_prefix}-${name}" if node.role == "worker"]
}
