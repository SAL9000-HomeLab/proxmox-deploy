# Roles

- [proxmox_clone](proxmox_clone/README.md) — clones VMs from Proxmox templates via SSH (`qm`),
  optionally reserving an IP from NetBox, and configures them with cloud-init (Linux) or over the
  QEMU guest agent (Windows).
- [windows_domain_member](windows_domain_member/README.md) — joins the deployed Windows VMs to
  Active Directory, adds the admin groups, enrolls an ADCS computer certificate and serves WinRM
  over HTTPS with it.
- `ans_ldap_auth` (from [ans-ldap-auth](https://github.com/SAL9000-HomeLab/ans-ldap-auth), installed by
  `requirements.yml`) — joins the deployed Linux VMs that have `domain_join` on to Active Directory with realmd and
  SSSD.
