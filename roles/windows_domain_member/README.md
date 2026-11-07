# windows_domain_member role

Turns a freshly deployed Windows Server VM into a domain member that other repositories can manage over WinRM
with Kerberos and HTTPS. `site.yml` runs it in its second play, against the `proxmox_deploy_windows` group that
[proxmox_clone](../proxmox_clone/README.md) fills with the Windows VMs it just deployed.

In order:

1. **Domain join.** Renames the computer and joins it to `windows_domain_member_domain`, creating the computer
   account in `windows_domain_member_ou`, in one step (`microsoft.ad.membership`), then reboots. A computer
   already in the domain is left alone.
2. **Local administrators.** Adds `windows_domain_member_admin_groups` to the local Administrators group.
3. **Certificate.** If the computer has no certificate WinRM HTTPS can use, it enrolls in the ADCS template
   `windows_domain_member_cert_template`, as SYSTEM so the request runs in machine context. Autoenrollment
   renews it from then on (with an autoenrollment GPO for the template).
4. **WinRM over HTTPS.** Binds the HTTPS listener (5986) to that certificate with the computer's FQDN as its
   hostname, and opens 5986 in the Windows firewall. A scheduled task (`\proxmox-deploy\WinRM HTTPS listener`)
   runs the same script at startup, daily and when autoenrollment replaces a certificate: a renewed certificate
   has a new thumbprint, and WinRM would otherwise keep serving the old one until it expires.
5. **Check.** Waits until 5986 answers from the controller.

The play connects as the local Administrator over PSRP with NTLM on 5985 (HTTP, with NTLM message encryption):
the VM isn't in the domain yet, so Kerberos isn't an option until after step 1. Every step is idempotent.

## The certificate

The listener script ([files/Set-WinRMHttpsListener.ps1](files/Set-WinRMHttpsListener.ps1)) uses the newest
certificate in `LocalMachine\My` that has its private key, is currently valid, isn't self-signed, has the
**Server Authentication** EKU (1.3.6.1.5.5.7.3.1), lists the computer's FQDN among its DNS names, and has a
subject CN naming the computer. The ADCS template therefore needs:

- **Application Policies / EKU:** Server Authentication. A copy of the built-in _Workstation Authentication_
  template only has Client Authentication: add Server Authentication to it (or base the template on _Computer_
  / _Web Server_). If the template issues a certificate without it, the role fails and lists the EKUs and DNS
  names the certificate has.
- **Subject Name:** built from Active Directory, with subject name format **Common name** and the DNS name
  included in the subject alternative name. WinRM matches the listener's hostname against the subject's CN and
  ignores the subject alternative name: with an empty subject (format "None", the Workstation Authentication
  default) creating the listener fails with "An internal error occurred". The listener's hostname is set to the
  CN, which may be the FQDN or the computer name; certificates without one are skipped and a new one enrolled.
- **Security:** Enroll (and Autoenroll, for renewals) for Domain Computers, or a group the servers are in, and
  issued without CA manager approval (the role fails on a pending request).

## Variables

All variables live in [defaults/main.yml](defaults/main.yml). Their defaults read the repository-wide variables
in `group_vars/all.yml` and the AWX credentials; proxmox_clone sets the per-VM ones as host variables.

| Variable | Default | Purpose |
| --- | --- | --- |
| `windows_domain_member_domain` | `domain_name` | AD DNS domain to join. |
| `windows_domain_member_ou` | `domain_join_ou`, per VM `domain_join_ou` | OU for the computer account (`""` = default Computers container). |
| `windows_domain_member_join_user` / `_join_password` | `domain_join_user` / `domain_join_pass` | Account that joins computers. `DOMAIN\user` or `user@domain`; a bare name gets `@<domain>`. |
| `windows_domain_member_hostname` | the VM's name | Computer name (15 characters at most). |
| `windows_domain_member_admin_groups` | `domain_admin_groups`, per VM `admin_groups` | Domain groups for local Administrators. A single `domain_admin_group` string is still read. |
| `windows_domain_member_cert_template` | `windows_cert_template`, per VM `cert_template` | ADCS template name (not its display name). `""` = don't enroll, use a certificate autoenrollment delivered. |
| `windows_domain_member_winrm_https` | `true` | Set up the HTTPS listener, firewall rule and scheduled task. |
| `windows_domain_member_script_dir` | `C:\ProgramData\proxmox-deploy` | Where the listener script is installed. |
| `windows_domain_member_reboot_timeout` | `900` | Seconds to wait for the VM after the domain-join reboot. |

## Managing the VMs afterwards

Once the play has run, other repositories (e.g. ans-defos) can reach the VM by its FQDN over PSRP with Kerberos
on 5986:

```yaml
ansible_connection: psrp
ansible_psrp_auth: kerberos
ansible_psrp_protocol: https
```

The local Administrator (`windows_admin_password`) stays available for break-glass access over NTLM.
