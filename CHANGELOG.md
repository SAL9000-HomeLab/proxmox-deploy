# Changelog

All notable changes to this project are documented here. Releases are cut by
pushing a `vX.Y.Z` tag; the release workflow publishes the matching section.

## [Unreleased]

- Changed: a VM's OS (Linux or Windows) comes from its template's Proxmox OS type (`ostype` starting with `w` =
  Windows), so `os_type` is no longer needed on each VM; it's still accepted as an override. Removed from the examples.
- Added: README sections on the inventory (the `proxmox` group, `node` after a VM migration), why the domain and
  NetBox variables must be job extra vars (playbook `group_vars` outrank inventory variables), and troubleshooting
  Windows deployments (first-boot diagnostics, the certificate subject, `qm guest exec` quoting).
- Fixed: the WinRM HTTPS listener needs a certificate whose subject CN names the computer (WinRM ignores the subject
  alternative name, and fails with "An internal error occurred" on an empty subject). Certificates without one are
  skipped and a new one enrolled; the listener's hostname is the certificate's CN (FQDN or computer name).
- Added: when a Windows clone never writes `SetupComplete.done`, the role inspects the guest (computer name, Windows
  Setup `ImageState`, its `SetupComplete.cmd`, the end of the setup log) and fails saying why, e.g. that the template
  predates vm-templates' clone answer file, instead of only timing out.
- Fixed: a re-run that reuses the IP already on a VM (`ipconfig0`) now checks NetBox has it, and reserves it again for
  the VM (same description, DNS name and tags) when the record is missing, so NetBox can't hand the address out.
- Fixed: NetBox v2 API tokens (`nbt_<key>.<token>`, the default since NetBox 4.5) are sent as `Bearer`; they were
  sent as `Token`, which NetBox rejects with "Invalid authorization header". v1 tokens still use `Token`.
- Changed: Windows VMs no longer use cloudbase-init (the vm-templates Windows Server 2025 templates don't ship it).
  proxmox_clone configures them over the QEMU guest agent instead: it waits for the template's unattended first
  boot (`SetupComplete.done`), then sets the static IP, gateway, DNS servers and search list, the timezone and a new
  local Administrator password (`windows_admin_password`) in the guest. The cloudbase-init templates and the
  `winrm_ssl` VM option are removed.
- Added: README instructions for the AWX credential type that injects `windows_admin_password` (the Machine
  credential is taken by the Proxmox SSH login).
- Added: `windows_domain_member` role, run by a second play in `site.yml` against the deployed Windows VMs over
  PSRP: joins the domain into the OU (renaming the computer), adds `domain_admin_groups` to local Administrators,
  enrolls an ADCS computer certificate from `windows_cert_template`, and serves WinRM over HTTPS on 5986 with it,
  with a scheduled task that rebinds the listener when autoenrollment renews the certificate.
- Changed: `domain_admin_group` (one group) is replaced by the `domain_admin_groups` list; the old variable is still
  read when the new one isn't set.
- Changed: VM names are now uppercased in Proxmox and in the NetBox `dns_name`, whatever case `name` is
  given in. Inside the guest, Linux hostnames are lowercase and Windows hostnames are uppercase. Only new
  clones get the new Proxmox name; an existing VM keeps its name.
- Fixed: The NetBox IP reservation gets a `dns_name` even when the VM has no `domain`; it falls back to
  `dns_zone`, then `technitium_dns.zone`, the same zone the Technitium A record uses.
- Fixed: Linux VMs now use the disk space `disk_size` adds. The Rocky templates put `/` on LVM and don't
  include `growpart`, so cloud-init never grew it and `/` stayed at the template's size. The user-data now
  installs `files/grow-root-fs.sh` and runs it on first boot to grow the partition, LVM physical and logical
  volume, and filesystem. VMs deployed earlier can be fixed with ans-cleanup's `playbook_grow_root_fs.yml`.
- Added: Pull-request linting for Markdown (markdownlint), links (linkspector) and YAML via the
  shared workflows, with `.markdownlint.json` and `.linkspector.yml`. The yamllint config is now
  `.yamllint.yml`, the name the shared `lint-yaml` workflow expects. Markdown fixed to pass.
- Added: CI on pushes to `main` and on pull requests (yamllint, playbook syntax check,
  ansible-lint) via the shared `SAL9000-HomeLab/shared-actions` workflow, with `.yamllint`
  and `.ansible-lint` configs. Tasks use FQCN module names and wrap at 120 columns.
- Added: Linux VMs get a key-based admin login (`linux_admin_user` / `linux_admin_ssh_keys`);
  the play fails before cloning a Linux VM that would get no SSH keys. (PR #14)
- Fixed: Rendered `/etc/resolv.conf` no longer has stray indentation. (PR #15)
- Changed: Example values replaced with placeholders; rendered userdata in `/tmp` is mode 0600
  and deleted after upload; MIT license added. (PR #13)
- Changed: Ansible CI runs on pull requests only, no longer on pushes to `main` (synced from ans-template).
