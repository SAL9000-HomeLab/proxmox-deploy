# proxmox_clone role

Purpose: clone VMs from Proxmox templates using SSH (`qm`), and configure them with a cloud-init snippet
(Linux) or over the QEMU guest agent (Windows).

Features:

- SSH-based flow (no Proxmox API required)
- Auto-allocates a vmid via `qm nextid` when `vmid` isn't supplied
- Idempotent: reconciles cores/memory, network bridge/VLAN, tags, description/notes,
  disk size, and cicustom/ipconfig/DNS against the VM's current `qm config` —
  only runs `qm set`/resize when something actually differs
- Optional NetBox IP allocation when `ip` isn't supplied — carries `description`, `domain`
  (as `dns_name`), and `tags` from `provision_vms` onto the NetBox IP reservation
- Windows: configures the guest over the QEMU guest agent (static IP, DNS, timezone, a new local
  Administrator password), then hands the VM to the [windows_domain_member](../windows_domain_member/README.md)
  play (domain join, local admins, ADCS certificate, WinRM over HTTPS)
- Waits for OS availability (SSH/WinRM) after starting a newly-cloned VM

Task layout (`tasks/`):

- `main.yml` — merges `proxmox_defaults`, validates `provision_vms`, loops per VM
- `provision_vm.yml` — thin orchestrator, imports the files below in order
- `resolve_vars.yml` — resolves per-VM settings and the target vmid
- `clone.yml` — clones the template (if needed) and gathers `qm config`
- `configure.yml` — reconciles cores/memory, network/VLAN, tags, description, disk size
- `cloudinit.yml` — renders/uploads the Linux userdata snippet, allocates a NetBox IP if needed,
  reconciles cicustom/ipconfig/DNS (Windows VMs get ipconfig/DNS only, so re-runs reuse their IP)
- `technitium_dns.yml` — creates the VM's Technitium A and associated PTR records when enabled
- `boot.yml` — starts the VM, runs `windows_guest.yml` for Windows, and waits for SSH (22) or WinRM (5985)
- `windows_guest.yml` — Windows only: waits for the guest agent and for the template's first-boot setup
  (`SetupComplete.done`), runs `templates/windows-guest-config.ps1.j2` in the guest as SYSTEM, and adds the
  VM to the `proxmox_deploy_windows` group for the next play

Usage:

- Pass `provision_vms` via AWX extra vars, inventory group vars, host_vars, or `group_vars/proxmox.yml`.
- Ensure inventory contains the Proxmox node and `ansible_python_interpreter` set.
- Run the role from a play that targets `proxmox` hosts.

Variable reference:

- `provision_vms`: list of VM objects.
  - `name` (required), `template_vmid` (required), `vmid` (optional — auto-allocated via
    `qm nextid` when omitted or `0`), `node` (optional, falls back to `proxmox.node` /
    `proxmox_defaults.node`), `storage` (optional, falls back to `proxmox.storage` /
    `proxmox_defaults.storage`).
  - OS: read from the template's Proxmox OS type (`ostype`). A Windows type (`win11`, `win10`, `w2k8`, … —
    all start with `w`) makes the VM Windows; anything else (`l26`, or `other` when the template doesn't set one)
    makes it Linux. The job log shows the result (`W25C-TEST001: windows (template 9001 ostype win11)`). `os_type`
    (`linux` or `windows`) on the VM overrides it; it's only needed for a template with a misleading `ostype`.
  - Name casing: `name` is uppercased for the Proxmox VM name and the NetBox `dns_name`, whatever
    case it's given in. The hostname set inside the guest (`hostname`, or `name` when that's unset)
    is lowercased on Linux and uppercased on Windows.
  - `net_bridge`, `net_model` (default `virtio`), `vlan`, `disk_target`, `cores` (default 2),
    `memory` (default 2048), `disk_size` (e.g. `100G` — only grows the disk, never shrinks; also
    applied to existing VMs). If `disk_target` isn't a disk on the VM, the boot disk is resized instead
    (with a warning). On a Linux VM's first boot, cloud-init runs `files/grow-root-fs.sh` to grow the
    root partition, LVM volume and filesystem into the new space. It doesn't run again, so after
    enlarging an existing VM's disk, grow it with ans-cleanup's `playbook_grow_root_fs.yml`.
  - `tags` (YAML list, or a comma-separated string such as `"windows,2025,core"`). Set as the VM's
    tags in Proxmox (`qm set --tags`; Proxmox creates new tags on the fly), and — only when NetBox
    allocates the IP (i.e. `ip` isn't supplied) — as the `tags` on that NetBox IP address
    reservation, sent as `{"name": "<tag>"}` objects. NetBox only looks up nested tags (it never
    creates them), so the role first creates any missing tag via `/api/extras/tags/` (slug =
    lowercased name, non `[a-z0-9_-]` chars replaced with `-`). Plain tag name strings are
    deliberately not used because NetBox interprets a numeric-looking string (e.g. a year like
    `"2025"`) as a tag object ID lookup rather than a name, which fails for any tag that hasn't
    already been created with that numeric ID.
  - `ip` (must include a CIDR prefix, e.g. `10.0.30.25/24` — Proxmox's `ipconfig0` rejects
    a bare IP), `gateway`, `dns_servers` (list), `search_domains` (list), `hostname`,
    `ssh_authorized_keys` (list, Linux only today — added to `linux_admin_user` on top of
    `linux_admin_ssh_keys`; see Templates note below).
  - `linked_clone`: `true` for a linked clone, `false` (default) for a full clone. Falls back to
    `proxmox_clone_behavior.linked_clone`, then `proxmox.linked_clone`, then `false`. Linked
    clones share the template's base disk: they're created on the template's storage (the
    `storage` setting is ignored), need storage that supports them (e.g. qcow2 on NFS/dir,
    LVM-thin, ZFS, Ceph), and keep the template in use for as long as the clone exists.
  - `full` (legacy): inverse of `linked_clone` (`false` = linked). Still honoured at each level
    (`full` per VM, `full_clone` in `proxmox_clone_behavior` / `proxmox`) when `linked_clone`
    isn't set at that level.
  - `description`: free-text note. Set as the VM's Notes field in Proxmox (`qm set --description`), and
    — only when NetBox allocates the IP (i.e. `ip` isn't supplied) — as the `description` on that
    NetBox IP address reservation.
  - `domain`: only used when NetBox allocates the IP (i.e. `ip` isn't supplied) — combined with
    the uppercased `name` as `<NAME>.<domain>` and set as the `dns_name` on that NetBox IP address reservation.
    Falls back to `dns_zone`, then `technitium_dns.zone`; with none of them set, no `dns_name` is sent.
    (Unrelated to the Windows domain-join variables below, despite the similar name.)
  - `timezone`: Windows only — a Windows time zone ID (e.g. `Eastern Standard Time`) set in the guest.
    Unset leaves the template's UTC. Linux VMs are currently hardcoded to `UTC` in
    `templates/linux-user-data.j2`, regardless of this field.
  - `domain_join_ou`, `admin_groups` (list), `cert_template`: Windows only — per-VM overrides of the
    [windows_domain_member](../windows_domain_member/README.md) OU, local admin groups and ADCS template.
  - `dns`: Linux only — a single nameserver string, used as a fallback in
    `templates/linux-user-data.j2` when `dns_servers` isn't set. Doesn't affect the Proxmox
    `--nameserver` config (which only reads `dns_servers`).
- `linux_admin_user` (default `ansible`) and `linux_admin_ssh_keys` (default `[]`): the account
  cloud-init sets up on Linux VMs, with passwordless sudo, a locked password, and these keys plus
  the VM's own `ssh_authorized_keys`. The vm-templates images ship this user locked with no key
  and SSH password auth off, so these keys are the only way in: the play fails before cloning a
  Linux VM that would get none. Set `linux_admin_ssh_keys` once (e.g. AWX extra vars or inventory).
- `proxmox`: role-level defaults (merged with `proxmox_defaults`).
  - `node`, `storage`, `snippets_dir`, `net_bridge`, `net_model`, `vlan`, `disk_target`,
    `linked_clone` (legacy `full_clone`), `cpu`, `memory`.
  - `proxmox_defaults` also defines `timeout` and `timezone` keys, but no current task reads
    them — setting them has no effect. (`timeout` is unrelated to the guest-wait timeout below.)
- `proxmox_clone_behavior`: optional dict, currently only `disk_target` and `linked_clone`
  (legacy `full_clone`) keys. Overrides `proxmox`/`proxmox_defaults` for those settings but is itself overridden by a
  per-VM value. No default is defined for this variable.
- `proxmox_clone_wait`: optional dict controlling the post-boot guest-reachability wait in
  `boot.yml` — `service_timeout` (seconds, default `600`) and `poll_interval` (seconds,
  default `5`). No default is defined for this variable.
- NetBox auto-allocation variables.
  - `netbox_allocate_ip`: true/false to enable NetBox allocation when `ip` is not supplied. If you
    want DHCP instead, set this to `false`.
  - `netbox_ip_ranges_by_bridge`: mapping from `net_bridge` to the NetBox IP range ID to allocate from.
  - `netbox_gateway_by_bridge`: mapping from `net_bridge` to the default gateway for that subnet.
  - `netbox`: API connection settings with `api_url`, `token`, and optional `ssl_verify`
    (defaults to `true`). `netbox_api_url` / `netbox_token` are accepted as flat fallbacks if
    `netbox.api_url` / `netbox.token` aren't set.
- Windows credentials (not part of `provision_vms` items; supply them from AWX credentials, the play
  fails before cloning a Windows VM without them):
  - `windows_admin_password`: the new local Administrator password, set once on the first deploy (it
    replaces the template's build password; later runs leave it alone). The domain play connects with it.
  - `domain_join_user` / `domain_join_pass`: the account that joins the VM to the domain.
  - The domain settings themselves (`domain_name`, `domain_join_ou`, `domain_admin_groups`,
    `windows_cert_template`) are read by [windows_domain_member](../windows_domain_member/README.md).

Templates:

- `templates/linux-user-data.j2` is the Linux cloud-init userdata. `templates/windows-guest-config.ps1.j2`
  is the PowerShell `windows_guest.yml` runs in Windows guests: it's written to a root-only file in `/run` on
  the node and reaches the guest on stdin (`qm guest exec --pass-stdin`), so the password is never on a
  command line, and it's deleted straight after.
- `files/grow-root-fs.sh` is embedded in the Linux user-data as `/usr/local/sbin/grow-root-fs` and run
  by `runcmd`. The same script is in ans-cleanup (`roles/grow_root_fs/files/`); keep the two identical.

AWX example:

```yaml
provision_vms:
  - name: W25C-TEST001
    description: "test vm deployment"
    domain: "lab.example.com"
    template_vmid: 9002  # tpl-windows-server-2025-core
    domain_join_ou: "OU=Build,OU=Servers,DC=ad,DC=example,DC=com"  # optional, overrides domain_join_ou
    node: pve01.lab.example.com
    vmid: 3021
    disk_target: scsi0
    net_bridge: vnet30
    # ip: 10.0.30.25/24
    # gateway: 10.0.30.1
    dns_servers:
      - 10.0.30.101
      - 10.0.30.111
    search_domains:
      - lab.example.com
      - ad.example.com
    cores: 4
    memory: 8192
    disk_size: 100G
    tags: "windows,2025,core"
proxmox:
  storage: nfs_ssd
  net_bridge: vnet30
```

Playbook usage:

```yaml
- hosts: proxmox
  roles:
    - role: proxmox_clone
      proxmox: "{{ proxmox | default({}) }}"
      provision_vms: "{{ provision_vms }}"
```

NetBox mapping example:

```yaml
netbox_allocate_ip: true
netbox_ip_ranges_by_bridge:
  vnet30: 19
netbox_gateway_by_bridge:
  vnet30: 10.0.30.1
netbox:
  api_url: "https://netbox.example.local"
  token: "YOUR_NETBOX_TOKEN"
  ssl_verify: true
```

Dependencies:

- Control host: none for the SSH flow. The Windows domain play needs `pypsrp` (see the repository's
  `requirements.txt`) and the `ansible.windows`, `community.windows` and `microsoft.ad` collections.
- Proxmox node: `qm` CLI must be available and accessible via SSH
- Windows templates: built by vm-templates with the clone answer file (QEMU guest agent installed, OOBE
  unattended, `SetupComplete.done` written on first boot)
