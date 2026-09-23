# proxmox_clone role

Purpose: clone VMs from Proxmox templates using SSH (`qm`) and cloud-init/cloudbase-init snippets.

Features:
- SSH-based flow (no Proxmox API required)
- Auto-allocates a vmid via `qm nextid` when `vmid` isn't supplied
- Idempotent: reconciles cores/memory, network bridge/VLAN, tags, description/notes,
  disk size, and cicustom/ipconfig/DNS against the VM's current `qm config` —
  only runs `qm set`/resize when something actually differs
- Optional NetBox IP allocation when `ip` isn't supplied — carries `description`, `domain`
  (as `dns_name`), and `tags` from `provision_vms` onto the NetBox IP reservation
- Waits for OS availability (SSH/WinRM) after starting a newly-cloned VM
- Uses Jinja2 templates for cloud-init and cloudbase-init userdata

Task layout (`tasks/`):
- `main.yml` — merges `proxmox_defaults`, validates `provision_vms`, loops per VM
- `provision_vm.yml` — thin orchestrator, imports the files below in order
- `resolve_vars.yml` — resolves per-VM settings and the target vmid
- `clone.yml` — clones the template (if needed) and gathers `qm config`
- `configure.yml` — reconciles cores/memory, network/VLAN, tags, description, disk size
- `cloudinit.yml` — renders/uploads the userdata snippet, allocates a NetBox IP if needed,
  reconciles cicustom/ipconfig/DNS
- `boot.yml` — starts the VM and waits for the guest to become reachable

Usage:
- Pass `provision_vms` via AWX extra vars, inventory group vars, host_vars, or `group_vars/proxmox.yml`.
- Ensure inventory contains the Proxmox node and `ansible_python_interpreter` set.
- Run the role from a play that targets `proxmox` hosts.

Variable reference:
- `provision_vms`: list of VM objects.
  - `name` (required), `template_vmid` (required), `vmid` (optional — auto-allocated via
    `qm nextid` when omitted or `0`), `node` (optional, falls back to `proxmox.node` /
    `proxmox_defaults.node`), `storage` (optional, falls back to `proxmox.storage` /
    `proxmox_defaults.storage`), `os_type` (`linux` or `windows`, default `linux`).
  - `net_bridge`, `net_model` (default `virtio`), `vlan`, `disk_target`, `cores` (default 2),
    `memory` (default 2048), `disk_size` (e.g. `100G` — only grows the disk, never shrinks; also
    applied to existing VMs). If `disk_target` isn't a disk on the VM, the boot disk is resized instead
    (with a warning).
  - `tags` (YAML list, or a comma-separated string such as `"windows,2025,core"`). Set as the VM's tags in Proxmox
    (`qm set --tags`; Proxmox creates new tags on the fly), and — only when NetBox allocates the IP (i.e. `ip` isn't supplied) — as the
    `tags` on that NetBox IP address reservation, sent as `{"name": "<tag>"}` objects. NetBox only
    looks up nested tags (it never creates them), so the role first creates any missing tag via
    `/api/extras/tags/` (slug = lowercased name, non `[a-z0-9_-]` chars replaced with `-`). Plain tag name strings are deliberately not used because NetBox
    interprets a numeric-looking string (e.g. a year like `"2025"`) as a tag object ID lookup rather
    than a name, which fails for any tag that hasn't already been created with that numeric ID.
  - `ip` (must include a CIDR prefix, e.g. `10.100.30.25/24` — Proxmox's `ipconfig0` rejects
    a bare IP), `gateway`, `dns_servers` (list), `search_domains` (list), `hostname`,
    `ssh_authorized_keys` (list, Linux only today — see Templates note below), `winrm_ssl`.
  - `full`: `true` for a full clone, `false` for a linked clone (default from
    `proxmox_clone_behavior.full_clone` / `proxmox.full_clone` / `proxmox_defaults.full_clone`, which is `false`).
  - `description`: free-text note. Set as the VM's Notes field in Proxmox (`qm set --description`), and
    — only when NetBox allocates the IP (i.e. `ip` isn't supplied) — as the `description` on that
    NetBox IP address reservation.
  - `domain`: only used when NetBox allocates the IP (i.e. `ip` isn't supplied) — combined with
    `name` as `<name>.<domain>` and set as the `dns_name` on that NetBox IP address reservation.
    (Unrelated to the Windows domain-join variables below, despite the similar name.)
  - `timezone`: Windows only — passed to cloudbase-init as `set_timezone`. Linux VMs are
    currently hardcoded to `UTC` in `templates/linux-user-data.j2`, regardless of this field.
  - `dns`: Linux only — a single nameserver string, used as a fallback in
    `templates/linux-user-data.j2` when `dns_servers` isn't set. Doesn't affect the Proxmox
    `--nameserver` config (which only reads `dns_servers`).
- `proxmox`: role-level defaults (merged with `proxmox_defaults`).
  - `node`, `storage`, `snippets_dir`, `net_bridge`, `net_model`, `vlan`, `disk_target`,
    `full_clone`, `cpu`, `memory`.
  - `proxmox_defaults` also defines `timeout` and `timezone` keys, but no current task reads
    them — setting them has no effect. (`timeout` is unrelated to the guest-wait timeout below.)
- `proxmox_clone_behavior`: optional dict, currently only `disk_target` and `full_clone` keys.
  Overrides `proxmox`/`proxmox_defaults` for those two settings but is itself overridden by a
  per-VM value. No default is defined for this variable.
- `proxmox_clone_wait`: optional dict controlling the post-boot guest-reachability wait in
  `boot.yml` — `service_timeout` (seconds, default `600`) and `poll_interval` (seconds,
  default `5`). No default is defined for this variable.
- NetBox auto-allocation variables.
  - `netbox_allocate_ip`: true/false to enable NetBox allocation when `ip` is not supplied. If you want DHCP instead, set this to `false`.
  - `netbox_ip_ranges_by_bridge`: mapping from `net_bridge` to the NetBox IP range ID to allocate from.
  - `netbox_gateway_by_bridge`: mapping from `net_bridge` to the default gateway for that subnet.
  - `netbox`: API connection settings with `api_url`, `token`, and optional `ssl_verify`
    (defaults to `true`). `netbox_api_url` / `netbox_token` are accepted as flat fallbacks if
    `netbox.api_url` / `netbox.token` aren't set.
- Windows domain-join variables (consumed directly by `templates/windows-cloudbase-init-userdata.j2`,
  not part of `provision_vms` items): `domain_name`, `domain_join_ou`, `domain_admin_group`,
  `domain_join_user`, `domain_join_pass`. `domain_name`/`domain_join_ou`/`domain_admin_group` are
  set in `group_vars/all.yml`; `domain_join_user`/`domain_join_pass` are not defined anywhere in
  this repo today and must be supplied as extra vars (e.g. via an AWX credential injected into the
  job) — `site.yml` does not load a credentials file for these.

Templates:
- `templates/linux-user-data.j2` and `templates/windows-cloudbase-init-userdata.j2` are the only
  two templates actually rendered (selected by `os_type` in `cloudinit.yml`).
- `templates/ref.j2` is an inactive reference/scratch template (not selected by any task) sketching
  possible future cloudbase-init options (`local_groups`, `admin_user`/`admin_groups`/`admin_password`,
  `ntp_servers`, Windows `ssh_authorized_keys`). None of those fields currently have any effect.

AWX example:
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
  vnet30: 10.100.30.1
netbox:
  api_url: "https://netbox.example.local"
  token: "YOUR_NETBOX_TOKEN"
  ssl_verify: true
```

Dependencies:
- Control host: none strictly required for the SSH flow (but you may want `pywinrm` if you plan to run Windows modules later)
- Proxmox node: `qm` CLI must be available and accessible via SSH
