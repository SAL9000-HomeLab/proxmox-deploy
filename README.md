# deploy-template

This repository deploys Windows VMs to a Proxmox cluster using SSH and `qm`.

Use `site.yml` from AWX and pass VM definitions through job extra vars.

Example AWX extra vars:
```yaml
provision_vms:
  - name: W25C-TEST001
    domain: "lab.sal9000.tech"
    template_vmid: 9001
    node: pve01.lab.sal9000.tech
    vmid: 3021
    disk_target: scsi0
    os_type: windows
    net_bridge: vnet30
    # ip: 10.100.30.25/24
    # gateway: 10.100.30.1
    dns_servers:
      - 10.100.30.101
      - 10.100.30.111
    search_domains:
      - lab.sal9000.tech
      - ds.sal9000.tech
    cores: 4
    memory: 8192
    disk_size: 100G
    tags: "windows,2025,core"
proxmox:
  storage: nfs_ssd
  net_bridge: vnet30
```

If you need credential files in AWX, set `proxmox_creds_file` and/or `domain_join_file` as extra vars.
