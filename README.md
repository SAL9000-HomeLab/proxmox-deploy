# proxmox-deploy

This repository deploys VMs (Linux or Windows) to a Proxmox cluster by cloning a template over
SSH (`qm`), optionally reserving an IP from NetBox, and configuring the guest: cloud-init on Linux,
the QEMU guest agent on Windows. Windows VMs are then joined to Active Directory and served over
WinRM with HTTPS. See [roles/README.md](roles/README.md) for the two roles and their variables.

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

Linux VMs need at least one SSH public key, because the templates have no usable password.
Set `linux_admin_ssh_keys` once (e.g. in AWX) and/or `ssh_authorized_keys` per VM. They're
installed for `linux_admin_user` (default `ansible`), which gets passwordless sudo.

## Windows VMs

Windows VMs come from the vm-templates Windows Server 2025 templates, which boot through OOBE
unattended (see vm-templates' "Windows clones"). Then, in `site.yml`:

1. **proxmox_clone** (first play) clones and starts the VM, waits for the QEMU guest agent and the
   template's first-boot setup, and runs a PowerShell script in the guest as SYSTEM: static IP,
   gateway, DNS servers and search list, the timezone (`timezone`, optional) and a new local
   Administrator password. It then waits for WinRM on 5985.
2. **windows_domain_member** (second play, over PSRP/NTLM as that Administrator) joins the domain
   into the OU and renames the computer, adds the admin groups to local Administrators, enrolls an
   ADCS computer certificate and binds the WinRM HTTPS listener (5986) to it, with a scheduled task
   that rebinds it when autoenrollment renews the certificate.

Afterwards the VM can be managed over PSRP with Kerberos on 5986 (as ans-defos does).

| Variable | Where | Purpose |
| --- | --- | --- |
| `windows_admin_password` | AWX credential | New local Administrator password (replaces the template's build password on the first deploy). |
| `domain_join_user` / `domain_join_pass` | AWX credential | Account that joins computers to the domain (`DOMAIN\user` or `user@domain`). |
| `domain_name`, `domain_join_ou` | `group_vars/all.yml` / AWX | Domain to join and the OU for new computer accounts (per VM: `domain_join_ou`). |
| `domain_admin_groups` | `group_vars/all.yml` / AWX | Domain groups added to local Administrators (per VM: `admin_groups`). |
| `windows_cert_template` | `group_vars/all.yml` / AWX | ADCS template to enroll in (per VM: `cert_template`). It must issue Server Authentication certificates; see [the role README](roles/windows_domain_member/README.md#the-certificate). |

The AWX execution environment needs `pypsrp` ([requirements.txt](requirements.txt)), and the
controller must reach the new VMs on 5985 and 5986.

## Development and CI

Two workflows call reusable workflows from
[`SAL9000-HomeLab/shared-actions`](https://github.com/SAL9000-HomeLab/shared-actions):

- **Ansible CI** (`.github/workflows/ansible-ci.yml`), on every pull request:
  - `yamllint`, then `ansible-playbook --syntax-check` on `site.yml`.
  - `ansible-lint` using [`.ansible-lint`](.ansible-lint). The only rule skipped is
    `var-naming[no-role-prefix]`: the role's variables (`provision_vms`, `proxmox`, `netbox`,
    `technitium_dns`, `linux_admin_*`, …) are set by AWX job templates and inventories, so
    prefixing them with `proxmox_clone_` would break existing callers.
- **Linting Validation** (`.github/workflows/ci.yml`), on pull requests to `main`:
  - Markdown lint (`markdownlint-cli2`) using [`.markdownlint.json`](.markdownlint.json):
    120-column lines (code blocks and tables exempt), `_emphasis_` and `**strong**`.
  - Link check (linkspector) using [`.linkspector.yml`](.linkspector.yml). Findings are
    reported on the pull request. Links to this org's GitHub repos are skipped.
  - `yamllint` again, standalone.

Both YAML checks read [`.yamllint.yml`](.yamllint.yml): the default rules with 120-column
lines (matching the editor ruler in `.vscode/settings.json`), with truthy checks skipped for
GitHub workflows (`on:`). The file must keep the `.yml` name, because the shared `lint-yaml`
workflow loads it by that exact path.

Run the same checks locally before opening a pull request:

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install "yamllint>=1.30" "ansible>=2.15" "ansible-lint>=6"
ansible-galaxy collection install -r requirements.yml
yamllint -f parsable .
ansible-playbook -i localhost, -c local --syntax-check site.yml
ansible-lint .
npx markdownlint-cli2 "**/*.md" "#.venv"
```

Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) with each change. Pushing a
`vX.Y.Z` tag publishes that version's section as a GitHub release.
