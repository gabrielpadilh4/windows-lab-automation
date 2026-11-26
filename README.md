# Ansible — Windows Server 2025 AD DS + AD CS

Promotes a fresh **Windows Server 2025** host to the first domain controller of a
**new AD forest**, then installs **AD CS** as a **Standalone Root CA**.

Connection: **WinRM over HTTPS** (pywinrm, NTLM).

## Layout

```
ansible.cfg                     # config (points at inventory, collections, vault pass)
requirements.yml                # Galaxy collections to install
inventory/hosts.yml             # target host(s)
group_vars/windows_dc/
  connection.yml                # WinRM connection settings
  ad.yml                        # AD DS + AD CS variables
  vault.yml.example             # secrets template -> copy to vault.yml (encrypted)
roles/ad_ds/                    # feature install + new-forest promotion
roles/ad_cs/                    # feature install + Standalone Root CA config
roles/ad_content/               # OUs, groups, users (data-driven)
roles/ad_cert_request/          # request + install a web-server cert from the CA
files/bootstrap-winrm.ps1       # run once ON the Windows host to enable WinRM
site.yml                        # main playbook
ping.yml                        # connectivity check
verify.yml                      # read-only post-build health check
.ansible-lint                   # lint config (production profile)
```

## Prerequisites

### Control node (this Linux box)

```bash
# Python WinRM client
python3 -m pip install --user "pywinrm>=0.4.3"

# Ansible collections (installed into ./collections, per ansible.cfg)
ansible-galaxy collection install -r requirements.yml -p collections
```

### Windows Server 2025 host

A fresh install with a reachable static IP and a local **Administrator** password.
Open an elevated PowerShell and run the bootstrap script (copy its contents, or
transfer the file):

```powershell
# from files/bootstrap-winrm.ps1
```

This enables an HTTPS WinRM listener on port 5986.

## Configure

1. Edit `inventory/hosts.yml` — set `ansible_host` to the server's IP.
2. Edit `group_vars/windows_dc/ad.yml` — domain name, NetBIOS, CA common name, etc.
3. Create the secrets file and encrypt it:

   ```bash
   cp group_vars/windows_dc/vault.yml.example group_vars/windows_dc/vault.yml
   # edit real passwords (12+ chars, meet Windows complexity), then:
   ansible-vault encrypt group_vars/windows_dc/vault.yml
   # store the vault password so ansible.cfg can read it:
   echo 'your-vault-password' > .vault_pass && chmod 600 .vault_pass
   ```

   > `vault_admin_password` is the local Administrator password *and* becomes the
   > `CORP\Administrator` password after promotion, so one value covers both phases.

## Run

```bash
ansible-playbook ping.yml      # verify WinRM auth
ansible-playbook site.yml      # full build (AD DS then AD CS)

# just one phase:
ansible-playbook site.yml --tags ad_ds
ansible-playbook site.yml --tags ad_cs
ansible-playbook site.yml --tags ad_content   # OUs/groups/users only
ansible-playbook site.yml --tags ad_cert_request
```

## AD content (ad_content role)

Define OUs, groups, and users as data in `group_vars/windows_dc/ad.yml`
(`ad_ous`, `ad_groups`, `ad_users`). The shipped example builds a `Corp` OU
tree with `App-Admins`/`App-Users` groups and two sample users. `ad_base_dn`
is derived automatically from the domain name. User passwords come from
`vault_user_default_password` in the vault; the create task uses `no_log`.

## Certificate request (ad_cert_request role)

Generates a PKCS#10 request (`certreq -new`) for a web-server certificate
(Server Authentication EKU + DNS SANs), submits it to the CA, and installs the
issued cert into `LocalMachine\My`. Because a **Standalone** CA pends requests
by default, the role auto-approves the pending request with `certutil -resubmit`
(valid here since Ansible runs as CA admin on the same host), then retrieves and
accepts it. It is idempotent — if a cert for the subject CN already exists with a
private key, it does nothing. CN/SANs default to the host FQDN; override with
`cert_request_subject_cn` / `cert_request_dns_sans`.

The AD DS promotion reboots the host automatically and waits for it to come
back. Re-running the playbook is idempotent.

## Verify

After a build, run the read-only health check (makes no changes):

```bash
ansible-playbook verify.yml
```

It reports the forest/domain, that NTDS/ADWS/DNS/Netlogon are running, the CA
state, the users created under `OU=Users,OU=Corp`, and any non-CA certificate
with a private key in `LocalMachine\My`.

## Lint

```bash
ansible-lint          # runs the 'production' profile from .ansible-lint
```

Embedded `win_powershell`/`certreq` scripts and shared cross-role AD vars are
accounted for in `.ansible-lint`.

## Notes

- **Standalone Root CA on a DC** is fine for a lab; Microsoft discourages
  co-locating the CA role on a DC in production (offline root is preferred).
- A Standalone CA does **not** support AD-integrated auto-enrollment or
  certificate templates. Switch `adcs_ca_type` to `EnterpriseRootCA` in
  `ad.yml` if you later want those (the host is already domain-joined).
- For production WinRM, replace the self-signed cert with a trusted one and set
  `ansible_winrm_server_cert_validation: validate`.
