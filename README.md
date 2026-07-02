# deploy-template

This repository deploys VMs (Linux or Windows) to a Proxmox cluster by cloning a template over
SSH (`qm`), optionally reserving an IP from NetBox, and applying cloud-init/cloudbase-init. All
of the actual logic lives in the `proxmox_clone` role — see
[roles/proxmox_clone/README.md](roles/proxmox_clone/README.md) for the full variable reference.

Use `site.yml` from AWX and pass VM definitions through job extra vars.

Example AWX extra vars:
```yaml
provision_vms:
  - name: W25C-TEST001
    description: "test vm deployment"
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
    tags: "windows,2025,core,ans-test"
proxmox:
  storage: nfs_ssd
  net_bridge: vnet30
```

Windows VMs also require the domain-join variables (`domain_name`, `domain_join_ou`,
`domain_admin_group`, `domain_join_user`, `domain_join_pass`) to be supplied as extra vars —
`site.yml` doesn't load a credentials file for these today, so they need to come from an AWX
credential injected into the job (or `-e` on the CLI). `domain_name`, `domain_join_ou`, and
`domain_admin_group` currently default from `group_vars/all.yml`.
