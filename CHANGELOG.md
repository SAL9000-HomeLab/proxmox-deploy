# Changelog

All notable changes to this project are documented here. Releases are cut by
pushing a `vX.Y.Z` tag; the release workflow publishes the matching section.

## [Unreleased]

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
