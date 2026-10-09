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
  windows2025_core: tpl-win2025-c
  windows2025_desktop: tpl-win2025-d
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
| `windows_admin_password` | Credential | New local Administrator password (replaces the template's build password on the first deploy). |
| `domain_join_user` / `domain_join_pass` | Credential | Account that joins computers to the domain (`DOMAIN\user` or `user@domain`). |
| `domain_name`, `domain_join_ou` | Job extra vars | Domain to join and the OU for new computer accounts (per VM: `domain_join_ou`). |
| `domain_admin_groups` | Job extra vars | Domain groups added to local Administrators (per VM: `admin_groups`). |
| `windows_cert_template` | Job extra vars | ADCS template to enroll in (per VM: `cert_template`). See [the certificate requirements](roles/windows_domain_member/README.md#the-certificate): Server Authentication, and subject name format **Common name**. |

Set the domain variables (and the NetBox maps, `netbox_ip_ranges_by_bridge` / `netbox_gateway_by_bridge`) as
**job template extra vars**, not as inventory variables. The placeholder values in this repository's
`group_vars/` sit next to `site.yml`, and Ansible ranks playbook `group_vars` above an AWX/Ascender
inventory's own variables, so inventory values are silently ignored. Only extra vars outrank them. A
`technitium_dns` or `proxmox` dictionary in extra vars replaces the repository's whole dictionary (no merge).

The execution environment needs `pypsrp` ([requirements.txt](requirements.txt)), and the controller must reach
the new VMs on 5985 and 5986. Tested with Ascender (an AWX distribution) running `site.yml`.

### Inventory

`site.yml`'s first play targets the inventory group **`proxmox`**: put every Proxmox node a VM can be deployed to
in it (`ansible_user: root`, `ansible_python_interpreter: /usr/bin/python3`), with the node's SSH key as the job's
Machine credential. A VM's `node` must be one of those host names exactly, because every `qm` command runs on it.
The second play's group (`proxmox_deploy_windows`) is filled by the first and needs no inventory entry.

`qm list` only shows the VMs on its own node. When a VM has been migrated to another node, set its `node` to the
node it's on now before re-running the job for it; otherwise the role looks for it on the old node, finds nothing
and tries to clone it again.

### AWX credential for the Windows Administrator password

The job template's Machine credential is already used for the SSH login to the Proxmox nodes, and a job
template takes only one Machine credential, so `windows_admin_password` comes from a custom credential type.

1. Under **Administration → Credential Types → Add**, name it `Windows local administrator` and paste:

   ```yaml
   # Input configuration
   fields:
     - id: windows_admin_password
       label: "Local Administrator password (new Windows VMs)"
       type: string
       secret: true
   required:
     - windows_admin_password
   ```

   ```yaml
   # Injector configuration
   extra_vars:
     windows_admin_password: "{{ windows_admin_password }}"
   ```

2. Under **Resources → Credentials → Add**, create a credential of type `Windows local administrator` with the
   password.
3. Attach it to the `site.yml` job template, next to the Machine credential (Proxmox SSH) and the credentials
   that supply `domain_join_user` / `domain_join_pass`, NetBox and Technitium.

The password is set once, on a VM's first deploy (it replaces the template's build password), and the domain
play then logs in with it. Changing the credential later doesn't change existing VMs; it only applies to VMs
deployed afterwards, so re-runs against older VMs need the password they were deployed with.

## Troubleshooting Windows deployments

- **"never finished its first boot: no SetupComplete.done"**: the role looked inside the guest and says why:
  - _was never generalized_ (the clone has the build's computer name and `IMAGE_STATE_UNDEPLOYABLE`): sysprep
    didn't finish when the template was built. Rebuild the template; current vm-templates fails the build when
    sysprep doesn't generalize.
  - _replayed the template build's answer file_ / _SetupComplete.cmd doesn't write SetupComplete.done_: the
    template predates vm-templates' clone answer file. Rebuild it.
  - _Windows Setup is still at …_: OOBE is waiting or failed; check the VM's console.

  Keep the VM until you've looked: delete it (and its NetBox and DNS records) only before the redeploy.
- **"An internal error occurred" creating the WinRM HTTPS listener**: the certificate has no subject CN. Set the
  ADCS template's subject name format to **Common name** and re-run; the role skips the CN-less certificate and
  enrolls a new one.
- **A re-run reuses an IP NetBox doesn't know**: the address in the VM's `ipconfig0` is reserved again in NetBox
  for the VM (the job log warns). To get a new address instead, `qm set <vmid> --delete ipconfig0` first.
- **Looking inside a VM** without network access: `qm guest exec` runs commands as SYSTEM over the guest agent.
  Single-quote the PowerShell for bash (in double quotes, bash treats a backtick as command substitution), and
  unwrap the JSON output:

  ```shell
  vmid=$(qm list | awk 'toupper($2) == "W25C-TEST001" {print $1}')
  qm guest exec "$vmid" --timeout 60 -- powershell.exe -NoProfile -Command 'hostname; Get-ChildItem Cert:\LocalMachine\My | Format-List Subject, Thumbprint, NotAfter' \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("out-data","")); print(d.get("err-data",""))'
  ```

  Run it on the node the VM is on now (`qm list` on each node).

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
