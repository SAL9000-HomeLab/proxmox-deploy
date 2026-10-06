<#
.SYNOPSIS
    Binds the WinRM HTTPS listener (5986) to this computer's ADCS certificate, enrolling one first if needed.

.DESCRIPTION
    Installed by the windows_domain_member role (proxmox-deploy) and run as SYSTEM: once by the deploy, and
    by the "WinRM HTTPS listener" scheduled task at startup, daily, and when autoenrollment replaces a
    certificate. A renewed certificate has a new thumbprint, and WinRM keeps serving the old one until it
    expires, so the listener has to be rebound.

    A usable certificate is in LocalMachine\My, has its private key, is currently valid, isn't self-signed,
    has the Server Authentication EKU and lists the computer's FQDN among its DNS names. The newest one wins.
    With -Template and no usable certificate, the computer enrolls in that ADCS template (machine context).

    Prints one line of JSON: changed, enrolled, thumbprint, expires.
#>
[CmdletBinding()]
param(
    [string]$DnsName = ('{0}.{1}' -f $env:COMPUTERNAME, (Get-CimInstance Win32_ComputerSystem).Domain).ToLower(),
    [string]$Template = ''
)
$ErrorActionPreference = 'Stop'
$serverAuth = '1.3.6.1.5.5.7.3.1'

function Get-UsableCertificate {
    $now = Get-Date
    Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.HasPrivateKey -and $_.NotBefore -le $now -and $_.NotAfter -gt $now -and
        $_.Issuer -ne $_.Subject -and
        $_.EnhancedKeyUsageList.ObjectId -contains $serverAuth -and
        $_.DnsNameList.Unicode -contains $DnsName
    } | Sort-Object NotAfter -Descending | Select-Object -First 1
}

$enrolled = $false
$cert = Get-UsableCertificate
if (-not $cert -and $Template) {
    $request = Get-Certificate -Template $Template -CertStoreLocation Cert:\LocalMachine\My
    if ($request.Status -ne 'Issued') {
        throw "Certificate request to template '$Template' was not issued (status: $($request.Status))."
    }
    $enrolled = $true
    $cert = Get-UsableCertificate
    if (-not $cert) {
        $issued = $request.Certificate
        throw ("Template '$Template' issued $($issued.Thumbprint), but WinRM HTTPS can't use it. It needs the " +
            "Server Authentication EKU ($serverAuth) and the DNS name $DnsName. EKUs: " +
            "$(($issued.EnhancedKeyUsageList.FriendlyName) -join ', '); DNS names: " +
            "$(($issued.DnsNameList.Unicode) -join ', '). Add Server Authentication to the template's " +
            "Application Policies and build the subject from the DNS name.")
    }
}
if (-not $cert) {
    throw "No usable certificate for $DnsName in LocalMachine\My (and no -Template to enroll from)."
}

$changed = $enrolled
$listener = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' }
$current = if ($listener) {
    $settings = Get-ChildItem $listener.PSPath
    [pscustomobject]@{
        Thumbprint = ($settings | Where-Object Name -eq 'CertificateThumbprint').Value
        Hostname   = ($settings | Where-Object Name -eq 'Hostname').Value
    }
}
if (-not $current -or $current.Thumbprint -ne $cert.Thumbprint -or $current.Hostname -ne $DnsName) {
    if ($listener) { $listener | Remove-Item -Recurse -Force }
    New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -HostName $DnsName `
        -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
    $changed = $true
}

[pscustomobject]@{
    changed    = $changed
    enrolled   = $enrolled
    thumbprint = $cert.Thumbprint
    expires    = $cert.NotAfter.ToString('o')
} | ConvertTo-Json -Compress
