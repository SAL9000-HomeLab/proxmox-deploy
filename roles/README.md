# Roles

- [proxmox_clone](proxmox_clone/README.md) — clones VMs from Proxmox templates via SSH (`qm`),
  optionally reserving an IP from NetBox, and configures them with cloud-init (Linux) or over the
  QEMU guest agent (Windows).
- [windows_domain_member](windows_domain_member/README.md) — joins the deployed Windows VMs to
  Active Directory, adds the admin groups, enrolls an ADCS computer certificate and serves WinRM
  over HTTPS with it.
