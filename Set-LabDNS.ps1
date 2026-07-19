#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Point Windows network adapter(s) at the lab BIND9 DNS server (keep DHCP for IP).

.DESCRIPTION
    Sets only DNS on the adapter — leaves IP/gateway on DHCP.
    Uses the lab nameserver alone (no public secondary) so Windows parallel DNS
    resolution cannot cache NXDOMAIN from 8.8.8.8 for names like pve.lab.
    Sets a connection-specific search suffix of "lab" and flushes the DNS cache.
    Optionally disables Windows DNS-over-HTTPS so lookups stay on the adapter DNS.

    Internet names still resolve via BIND recursion + forwarders on the Proxmox host.

.PARAMETER AdapterName
    Adapter to configure (e.g. "Ethernet", "Wi-Fi"). If omitted, all Up adapters.

.PARAMETER DnsServer
    Lab DNS server IP. Default: 10.0.0.10 (Proxmox / BIND9).

.PARAMETER DnsSuffix
    Connection-specific DNS suffix. Default: lab.

.PARAMETER DisableDoh
    Disable DNS-over-HTTPS (auto DoH) so Windows does not bypass adapter DNS.
    Default: $true.

.PARAMETER SkipConfirm
    Apply without interactive confirmation.

.EXAMPLE
    .\Set-LabDNS.ps1
    Configure all active adapters to use 10.0.0.10 and suffix "lab".

.EXAMPLE
    .\Set-LabDNS.ps1 -AdapterName "Ethernet"
    Configure only the Ethernet adapter.

.EXAMPLE
    .\Set-LabDNS.ps1 -DnsServer "10.0.0.10" -SkipConfirm
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$AdapterName,

    [Parameter(Mandatory = $false)]
    [string]$DnsServer = "10.0.0.10",

    [Parameter(Mandatory = $false)]
    [string]$DnsSuffix = "lab",

    [Parameter(Mandatory = $false)]
    [bool]$DisableDoh = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirm
)

function Test-IsValidIPv4 {
    param([string]$IP)
    return $IP -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

if (-not (Test-IsValidIPv4 $DnsServer)) {
    Write-Host "ERROR: Invalid DNS server address: $DnsServer" -ForegroundColor Red
    exit 1
}

# Resolve adapters
if ($AdapterName) {
    $adapters = @(Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName })
    if (-not $adapters) {
        Write-Host "ERROR: Adapter '$AdapterName' not found" -ForegroundColor Red
        Write-Host "`nAvailable adapters:" -ForegroundColor Yellow
        Get-NetAdapter | Format-Table Name, Status, InterfaceDescription -AutoSize
        exit 1
    }
} else {
    $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    if (-not $adapters) {
        Write-Host "ERROR: No active (Up) network adapters found" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n=== Lab DNS Configuration ===" -ForegroundColor Cyan
Write-Host "Adapters:    $($adapters.Name -join ', ')"
Write-Host "DNS server:  $DnsServer  (lab only — no public secondary)"
Write-Host "DNS suffix:  $DnsSuffix"
Write-Host "IP mode:     unchanged (DHCP or existing static kept)"
Write-Host "Disable DoH: $DisableDoh"
Write-Host ""

if (-not $SkipConfirm) {
    $confirmation = Read-Host "Apply this configuration? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "Aborted by user" -ForegroundColor Yellow
        exit 0
    }
}

foreach ($adapter in $adapters) {
    Write-Host "`nConfiguring: $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor Cyan

    $before = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    Write-Host "  Current DNS: $($before.ServerAddresses -join ', ')" -ForegroundColor Gray

    try {
        # Lab DNS only — do not append 8.8.8.8 (Windows SMHNR races public NXDOMAIN)
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses @($DnsServer)
        Write-Host "  DNS set to $DnsServer" -ForegroundColor Green

        Set-DnsClient -InterfaceIndex $adapter.InterfaceIndex `
            -ConnectionSpecificSuffix $DnsSuffix `
            -RegisterThisConnectionsAddress $true `
            -UseSuffixWhenRegistering $false
        Write-Host "  Connection-specific suffix set to '$DnsSuffix'" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($DisableDoh) {
    Write-Host "`nDisabling automatic DNS-over-HTTPS (so lookups use adapter DNS)..." -ForegroundColor Yellow
    try {
        # EnableAutoDoh: 0 = off, 1 = probe, 2 = always (Win10 19628+ / Win11)
        $dohPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        if (Test-Path $dohPath) {
            New-ItemProperty -Path $dohPath -Name EnableAutoDoh -PropertyType DWord -Value 0 -Force | Out-Null
            Write-Host "  EnableAutoDoh = 0" -ForegroundColor Green
        }
        # Clear any configured DoH server templates if cmdlet exists
        if (Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
            Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-DnsClientDohServerAddress -ServerAddress $_.ServerAddress -ErrorAction SilentlyContinue
                } catch { }
            }
            Write-Host "  Cleared DnsClient DoH server addresses (if any)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  WARNING: Could not fully disable DoH: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Manually: Settings → Network → adapter → DNS → DNS over HTTPS: Off" -ForegroundColor Yellow
    }
}

Clear-DnsClientCache
Write-Host "`nDNS cache flushed" -ForegroundColor Green

Start-Sleep -Seconds 1

Write-Host "`n=== Verification ===" -ForegroundColor Cyan
foreach ($adapter in $adapters) {
    $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    $client = Get-DnsClient -InterfaceIndex $adapter.InterfaceIndex
    Write-Host "$($adapter.Name):" -ForegroundColor White
    Write-Host "  DNS:    $($dns.ServerAddresses -join ', ')" -ForegroundColor Green
    Write-Host "  Suffix: $($client.ConnectionSpecificSuffix)" -ForegroundColor Green
}

Write-Host "`n=== Connectivity / resolution tests ===" -ForegroundColor Cyan
Write-Host "ICMP to DNS server $DnsServer..."
if (Test-Connection -ComputerName $DnsServer -Count 2 -Quiet) {
    Write-Host "  Reachable" -ForegroundColor Green
} else {
    Write-Host "  WARNING: ICMP failed (firewall may block ping; DNS may still work)" -ForegroundColor Yellow
}

Write-Host "Direct query via $DnsServer for pve.lab..."
try {
    $direct = Resolve-DnsName -Name "pve.lab" -Server $DnsServer -Type A -ErrorAction Stop |
        Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
    if ($direct) {
        Write-Host "  pve.lab -> $($direct.IPAddress)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: No A record returned for pve.lab" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  On Proxmox check: systemctl status named; dig @$DnsServer pve.lab +short" -ForegroundColor Yellow
}

Write-Host "System resolution for pve.lab (what ping uses)..."
try {
    $sys = Resolve-DnsName -Name "pve.lab" -Type A -ErrorAction Stop |
        Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
    if ($sys) {
        Write-Host "  pve.lab -> $($sys.IPAddress)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: No A record from system resolver" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nDone. Revert with: .\Reset-DNS.ps1`n" -ForegroundColor Green
