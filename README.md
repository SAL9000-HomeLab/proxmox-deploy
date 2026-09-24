# proxmox-deploy

This repository deploys VMs (Linux or Windows) to a Proxmox cluster by cloning a template over
SSH (`qm`), optionally reserving an IP from NetBox, and applying cloud-init/cloudbase-init. All
of the actual logic lives in the `proxmox_clone` role — see
[roles/proxmox_clone/README.md](roles/proxmox_clone/README.md) for the full variable reference.

Use `site.yml` from AWX and pass VM definitions through job extra vars.

The values committed in `inventory/` and `group_vars/` (`example.com`, `10.0.x.x`, the
`pve01` node, NetBox range IDs) are placeholders. Supply your real environment through your
AWX inventory and job extra vars, or local files that are gitignored (`local/`,
`extra-vars*.yml`). Never commit credentials.

## Template catalog contract

The image-building repo owns the template identity. This repo consumes those canonical template
names and applies runtime values such as VM name, IP, gateway, DNS, and tags at deployment time.

```yaml
template_catalog:
  rocky9: tpl-rocky-9
  rocky10: tpl-rocky-10
  ubuntu2404: tpl-ubuntu-2404
  windows2025_core: tpl-windows-server-2025-core
  windows2025_desktop: tpl-windows-server-2025-desktop
```

The deploy repo should never invent a template name on the fly. It should reference the template
name already created in the VM template repo and then set per-instance values separately.

Example AWX extra vars:
```yaml
provision_vms:
  - name: rocky10-web-01
    template: tpl-rocky-10
    template_vmid: 10001
    node: pve01.lab.example.com
    vmid: 3101
    disk_target: scsi0
    os_type: linux
    net_bridge: vnet30
    ip: 10.0.30.11/24
    gateway: 10.0.30.1
    dns_servers:
      - 10.0.30.101
      - 10.0.30.111
    search_domains:
      - lab.example.com
    cores: 2
    memory: 4096
    disk_size: 40G
    tags:
      - rocky
      - linux
      - web
proxmox:
  storage: nfs_ssd
  net_bridge: vnet30

technitium_dns:
  enabled: true
  api_port: 53443
  validate_certs: false
  zone: "lab.example.com"
  ttl: 3600
  create_ptr_zone: true
```

When enabled, each VM creates an A record named `<name>.<zone>` and its associated
PTR record. A VM can override the forward zone with `dns_zone`, or the full name with
`dns_name`.

For AWX, inject the credential as `technitium_dns_api_url` and
`technitium_dns_api_token`. Keep the API token out of job extra vars.

Windows VMs also require the domain-join variables (`domain_name`, `domain_join_ou`,
`domain_admin_group`, `domain_join_user`, `domain_join_pass`) to be supplied as extra vars —
`site.yml` doesn't load a credentials file for these today, so they need to come from an AWX
credential injected into the job (or `-e` on the CLI). `domain_name`, `domain_join_ou`, and
`domain_admin_group` currently default from `group_vars/all.yml`.
