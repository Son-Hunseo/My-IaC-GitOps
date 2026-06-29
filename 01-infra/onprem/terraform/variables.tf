variable "proxmox_endpoint" {
  # 한국어 주석: Proxmox API endpoint는 환경마다 다르므로 기본값을 두지 않습니다.
  description = "Proxmox VE API endpoint URL. Example: https://proxmox.example.local:8006/"
  type        = string
}

variable "proxmox_api_token_id" {
  # 한국어 주석: API token ID도 민감 정보로 취급해 plan/output 노출을 줄입니다.
  description = "Proxmox API token ID. Example: terraform@pve!gitops"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  # 한국어 주석: 실제 token secret은 tfvars.example에 넣지 않고 런타임에만 주입합니다.
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  # 한국어 주석: 기본값은 TLS 검증 활성화이며, 자체 서명 인증서 환경에서만 true로 변경합니다.
  description = "Allow insecure TLS for Proxmox API connections. Use false when a trusted certificate is available."
  type        = bool
  default     = false
}

variable "proxmox_node_name" {
  # 한국어 주석: VM을 생성할 Proxmox compute node를 명시합니다.
  description = "Proxmox node where VMs will be created."
  type        = string
}

variable "vm_template_id" {
  # 한국어 주석: OS 설치를 Terraform에서 수행하지 않고 준비된 cloud-init template을 clone합니다.
  description = "Existing Proxmox VM template ID used as the clone source."
  type        = number
}

variable "vm_template_node_name" {
  # 한국어 주석: template이 다른 Proxmox node에 있을 수 있어 별도 입력을 허용합니다.
  description = "Proxmox node containing the VM template. Defaults to proxmox_node_name when null."
  type        = string
  default     = null
}

variable "vm_id_start" {
  # 한국어 주석: VM ID 충돌을 피하기 위해 환경별 시작 번호를 조정할 수 있습니다.
  description = "Base VM ID. master starts at this value and workers increment from it."
  type        = number
  default     = 3000
}

variable "vm_name_prefix" {
  # 한국어 주석: 동일 Proxmox 환경에서 여러 실험 환경을 구분하기 위한 이름 prefix입니다.
  description = "Prefix for generated VM names."
  type        = string
  default     = "gitops-k8s"
}

variable "vm_description" {
  # 한국어 주석: Proxmox 콘솔에서 Terraform 관리 리소스임을 식별할 수 있게 설명을 남깁니다.
  description = "Description written to Proxmox VM metadata."
  type        = string
  default     = "Provisioned by Terraform for future Kubernetes bootstrap."
}

variable "datastore_id" {
  # 한국어 주석: VM root disk가 생성될 datastore입니다.
  description = "Proxmox datastore used for VM disks."
  type        = string
}

variable "cloud_init_datastore_id" {
  # 한국어 주석: cloud-init snippet을 별도 datastore에 보관하는 환경을 지원합니다.
  description = "Proxmox datastore used for cloud-init snippets. Defaults to datastore_id when null."
  type        = string
  default     = null
}

variable "disk_interface" {
  # 한국어 주석: template과 호환되는 disk bus/interface 값을 사용해야 합니다.
  description = "Disk interface used by cloned VMs."
  type        = string
  default     = "scsi0"
}

variable "disk_file_format" {
  # 한국어 주석: datastore 유형에 맞게 raw 또는 qcow2 등을 선택할 수 있습니다.
  description = "Disk file format for VM disks."
  type        = string
  default     = "raw"
}

variable "network_bridge" {
  # 한국어 주석: VM NIC가 연결될 Proxmox bridge입니다.
  description = "Proxmox network bridge attached to each VM."
  type        = string
  default     = "vmbr0"
}

variable "network_model" {
  # 한국어 주석: Linux VM에서 일반적으로 사용하는 virtio NIC 모델을 기본값으로 둡니다.
  description = "Virtual NIC model."
  type        = string
  default     = "virtio"
}

variable "network_vlan_id" {
  # 한국어 주석: VLAN을 사용하지 않는 flat network 환경은 null을 유지합니다.
  description = "Optional VLAN ID for VM network interfaces. Use null for untagged traffic."
  type        = number
  default     = null
}

variable "gateway_ipv4" {
  # 한국어 주석: 모든 VM에 동일한 IPv4 기본 gateway를 주입합니다.
  description = "Default IPv4 gateway used by all VMs."
  type        = string
}

variable "dns_servers" {
  # 한국어 주석: cloud-init으로 VM 내부 resolver 설정을 초기화합니다.
  description = "DNS servers injected through cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "cloud_init_username" {
  # 한국어 주석: template OS의 cloud-init 사용자 정책과 일치해야 합니다.
  description = "Initial Linux user created or configured by cloud-init."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  # 한국어 주석: 공개키만 입력하며 개인키는 절대 Terraform 변수 파일에 저장하지 않습니다.
  description = "SSH public keys authorized for the cloud-init user."
  type        = list(string)
  default     = []
}

variable "vm_nodes" {
  # 한국어 주석: Kubernetes 설치 전 단계이므로 role은 VM 용량과 식별 목적으로만 사용합니다.
  description = "VM node definitions. ip_address must include CIDR prefix, for example 192.168.10.11/24."
  type = map(object({
    role       = string
    vm_id      = optional(number)
    ip_address = string
    cores      = number
    memory_mb  = number
    disk_gb    = number
  }))

  default = {
    master-01 = {
      role       = "master"
      ip_address = "192.168.10.11/24"
      cores      = 4
      memory_mb  = 8192
      disk_gb    = 128
    }
    worker-01 = {
      role       = "worker"
      ip_address = "192.168.10.21/24"
      cores      = 2
      memory_mb  = 4096
      disk_gb    = 128
    }
    worker-02 = {
      role       = "worker"
      ip_address = "192.168.10.22/24"
      cores      = 2
      memory_mb  = 4096
      disk_gb    = 128
    }
  }

  validation {
    condition     = length([for name, node in var.vm_nodes : name if node.role == "master"]) == 1
    error_message = "Exactly one VM node must use role = \"master\"."
  }

  validation {
    condition     = length([for name, node in var.vm_nodes : name if node.role == "worker"]) == 2
    error_message = "Exactly two VM nodes must use role = \"worker\"."
  }
}
