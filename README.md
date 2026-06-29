# deploy-template

This repository deploys Windows VMs to a Proxmox cluster using SSH and `qm`.

Use `deploy_windows.yml` from AWX and pass VM definitions through job extra vars.

Example AWX extra vars:
```yaml
provision_vms:
  - name: W25C-LABDC006
    template_vmid: 9001
    node: pve01.lab.sal9000.tech
    vmid: 3026
    disk_target: scsi0
    os_type: windows
    net_bridge: vnet30
    ip: 10.100.30.12/24
    gateway: 10.100.30.1
    dns: 10.100.30.101 10.100.30.111
    cores: 4
    memory: 8192
    disk_size: 100G
    tags: "windows,2025,core"
proxmox:
  storage: nfs_ssd
  net_bridge: vnet30
```

If you need credential files in AWX, set `proxmox_creds_file` and/or `domain_join_file` as extra vars.
