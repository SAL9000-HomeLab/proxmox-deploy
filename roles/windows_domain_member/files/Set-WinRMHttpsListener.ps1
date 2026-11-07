<#
.SYNOPSIS
    Binds the WinRM HTTPS listener (5986) to this computer's ADCS certificate, enrolling one first if needed.

.DESCRIPTION
    Installed by the windows_domain_member role (proxmox-deploy) and run as SYSTEM: once by the deploy, and
    by the "WinRM HTTPS listener" scheduled task at startup, daily, and when autoenrollment replaces a
    certificate. A renewed certificate has a new thumbprint, and WinRM keeps serving the old one until it
    expires, so the listener has to be rebound.

    A usable certificate is in LocalMachine\My, has its private key, is currently valid, isn't self-signed,
    has the Server Authentication EKU, lists the computer's FQDN among its DNS names, and has a subject common
    name (CN) that is the FQDN or the computer name: WinRM matches the listener's hostname against the CN, not
    the subject alternative name, and won't create a listener for a certificate with an empty subject ("An
    internal error occurred"). The newest one wins, and the listener's hostname is set to its CN. With
    -Template and no usable certificate, the computer enrolls in that ADCS template (machine context).

    Prints one line of JSON: changed, enrolled, thumbprint, hostname (the listener's, from the CN), expires.
#>
[CmdletBinding()]
param(
    [string]$DnsName = ('{0}.{1}' -f $env:COMPUTERNAME, (Get-CimInstance Win32_ComputerSystem).Domain).ToLower(),
    [string]$Template = ''
)
$ErrorActionPreference = 'Stop'
$serverAuth = '1.3.6.1.5.5.7.3.1'
$computerNames = @($DnsName, $env:COMPUTERNAME)

# The subject's CN (GetNameInfo SimpleName falls back to other name types, so read the CN itself).
function Get-SubjectCN($Certificate) {
    if ($Certificate.Subject -match '(?:^|,\s*)CN=([^,]+)') { $Matches[1].Trim() } else { '' }
}

function Get-UsableCertificate {
    $now = Get-Date
    Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.HasPrivateKey -and $_.NotBefore -le $now -and $_.NotAfter -gt $now -and
        $_.Issuer -ne $_.Subject -and
        $_.EnhancedKeyUsageList.ObjectId -contains $serverAuth -and
        $_.DnsNameList.Unicode -contains $DnsName -and
        $computerNames -contains (Get-SubjectCN $_)
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
            "Server Authentication EKU ($serverAuth), the DNS name $DnsName and a subject CN of $DnsName or " +
            "$env:COMPUTERNAME. Subject: '$($issued.Subject)'; EKUs: " +
            "$(($issued.EnhancedKeyUsageList.FriendlyName) -join ', '); DNS names: " +
            "$(($issued.DnsNameList.Unicode) -join ', '). In the template, add Server Authentication to " +
            "Application Policies, and on Subject Name build from AD with subject name format 'Common name' " +
            "and the DNS name included.")
    }
}
if (-not $cert) {
    throw "No usable certificate for $DnsName in LocalMachine\My (and no -Template to enroll from)."
}

$changed = $enrolled
$hostname = Get-SubjectCN $cert
$listener = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' }
$current = if ($listener) {
    $settings = Get-ChildItem $listener.PSPath
    [pscustomobject]@{
        Thumbprint = ($settings | Where-Object Name -eq 'CertificateThumbprint').Value
        Hostname   = ($settings | Where-Object Name -eq 'Hostname').Value
    }
}
if (-not $current -or $current.Thumbprint -ne $cert.Thumbprint -or $current.Hostname -ne $hostname) {
    if ($listener) { $listener | Remove-Item -Recurse -Force }
    New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -HostName $hostname `
        -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
    $changed = $true
}

[pscustomobject]@{
    changed    = $changed
    enrolled   = $enrolled
    thumbprint = $cert.Thumbprint
    hostname   = $hostname
    expires    = $cert.NotAfter.ToString('o')
} | ConvertTo-Json -Compress
