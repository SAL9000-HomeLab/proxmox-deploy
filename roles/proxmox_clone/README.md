# proxmox_clone role

Purpose: clone VMs from Proxmox templates using SSH (`qm`) and cloud-init/cloudbase-init snippets.

Features:
- SSH-based flow (no Proxmox API required)
- Idempotent: detects existing VM and cicustom/ipconfig differences
- Waits for OS availability (SSH/WinRM)
- Uses Jinja2 templates for cloud-init and cloudbase-init userdata

Usage:
- Set `provision_vms` in `group_vars/proxmox.yml`.
- Ensure inventory contains the Proxmox node and `ansible_python_interpreter` set.
- Run the role from a play that targets `proxmox` hosts.

Dependencies:
- Control host: none strictly required for the SSH flow (but you may want `pywinrm` if you plan to run Windows modules later)
- Proxmox node: `qm` CLI must be available and accessible via SSH

Example:
```yaml
- hosts: proxmox
  roles:
    - proxmox_clone
