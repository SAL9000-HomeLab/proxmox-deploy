# proxmox_clone role

Purpose: clone VMs from Proxmox templates using SSH (`qm`) and cloud-init/cloudbase-init snippets.

Features:
- SSH-based flow (no Proxmox API required)
- Idempotent: detects existing VM and cicustom/ipconfig differences
- Waits for OS availability (SSH/WinRM)
- Uses Jinja2 templates for cloud-init and cloudbase-init userdata

Usage:
- Pass `provision_vms` via AWX extra vars, inventory group vars, host_vars, or `group_vars/proxmox.yml`.
- Ensure inventory contains the Proxmox node and `ansible_python_interpreter` set.
- Run the role from a play that targets `proxmox` hosts.

AWX example:
```yaml
provision_vms:
  - name: W25C-LABDC006
    template_vmid: 9001
    node: pve01.lab.sal9000.tech
    vmid: 3026
    disk_target: scsi0
    os_type: windows
    net_bridge: vlan30
    ip: 10.100.30.12/24
    gateway: 10.100.30.1
    dns: 10.100.30.101 10.100.30.111
    cores: 4
    memory: 8192
    disk_size: 100G
    tags: "windows,2025,core"
proxmox:
  storage: nfs_ssd
  net_bridge: vmbr0
```
```yaml
- hosts: proxmox
  roles:
    - role: proxmox_clone
      proxmox: "{{ proxmox | default({}) }}"
      provision_vms: "{{ provision_vms }}"
```
```text
# In AWX extra vars using YAML format
provision_vms: ...
proxmox:
  storage: nfs_ssd
  net_bridge: vmbr0
```

Dependencies:
- Control host: none strictly required for the SSH flow (but you may want `pywinrm` if you plan to run Windows modules later)
- Proxmox node: `qm` CLI must be available and accessible via SSH

Example:
```yaml
- hosts: proxmox
  roles:
    - proxmox_clone
