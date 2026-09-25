# Changelog

All notable changes to this project are documented here. Releases are cut by
pushing a `vX.Y.Z` tag; the release workflow publishes the matching section.

## [Unreleased]

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
