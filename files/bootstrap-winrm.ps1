<#
    Run this ONCE on the fresh Windows Server 2025 host (in an elevated
    PowerShell prompt) to enable HTTPS WinRM for Ansible.

    It creates a self-signed cert, an HTTPS listener, opens the firewall,
    and enables Basic/NTLM so pywinrm can connect. For a lab only — in
    production use a CA-issued certificate and disable Basic auth.
#>

$ErrorActionPreference = "Stop"

# Enable PowerShell remoting / WinRM service.
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Remove any existing HTTPS listener, then create a fresh one.
Get-ChildItem WSMan:\localhost\Listener |
    Where-Object { $_.Keys -contains "Transport=HTTPS" } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My

New-Item -Path WSMan:\localhost\Listener `
    -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force

# Firewall rule for WinRM over HTTPS (5986).
New-NetFirewallRule -DisplayName "WinRM HTTPS (5986)" `
    -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow `
    -ErrorAction SilentlyContinue

# Auth methods used by pywinrm (ntlm transport).
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true

Write-Host "WinRM HTTPS listener ready on port 5986." -ForegroundColor Green
