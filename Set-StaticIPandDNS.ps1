#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configure static IP address and DNS servers on a Windows 11 network adapter.

.DESCRIPTION
    Sets a static IPv4 address, gateway, and DNS servers on the specified network adapter.
    This prevents DHCP from overriding DNS settings after reboot.
    Also disables IPv6 to prevent IPv6 DNS servers from taking precedence over IPv4 DNS.

.PARAMETER AdapterName
    Name of the network adapter to configure (e.g., "Ethernet", "Wi-Fi").

.PARAMETER IPAddress
    Static IP address to assign (e.g., "10.0.0.50").

.PARAMETER PrefixLength
    Network prefix length (subnet mask in CIDR notation). Default is 24 (/24 = 255.255.255.0).

.PARAMETER Gateway
    Default gateway IP address (e.g., "10.0.0.1").

.PARAMETER DnsServers
    Array of DNS server IP addresses. First will be primary, second will be secondary.

.EXAMPLE
    .\Set-StaticIPandDNS.ps1 -AdapterName "Ethernet" -IPAddress "10.0.0.50" -Gateway "10.0.0.1" -DnsServers "10.0.0.10","8.8.8.8"
    Sets static IP 10.0.0.50/24 with gateway 10.0.0.1 and DNS servers 10.0.0.10, 8.8.8.8

.EXAMPLE
    .\Set-StaticIPandDNS.ps1 -AdapterName "Wi-Fi" -IPAddress "10.0.0.51" -Gateway "10.0.0.1" -DnsServers "10.0.0.10"
    Sets static configuration with single DNS server

.NOTES
    This will disable DHCP on the adapter. Make sure the IP address you choose doesn't conflict
    with other devices and is outside your DHCP range.

    IPv6 will be disabled on the adapter to prevent Windows from preferring IPv6 DNS servers
    over the configured IPv4 DNS servers.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$AdapterName,

    [Parameter(Mandatory=$true)]
    [string]$IPAddress,

    [Parameter(Mandatory=$false)]
    [int]$PrefixLength = 24,

    [Parameter(Mandatory=$true)]
    [string]$Gateway,

    [Parameter(Mandatory=$true)]
    [string[]]$DnsServers
)

function Validate-IPAddress {
    param([string]$IP)
    return $IP -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

# Validate inputs
Write-Host "`nValidating inputs..." -ForegroundColor Yellow

if (-not (Validate-IPAddress $IPAddress)) {
    Write-Host "ERROR: Invalid IP address format: $IPAddress" -ForegroundColor Red
    exit 1
}

if (-not (Validate-IPAddress $Gateway)) {
    Write-Host "ERROR: Invalid gateway address format: $Gateway" -ForegroundColor Red
    exit 1
}

foreach ($dns in $DnsServers) {
    if (-not (Validate-IPAddress $dns)) {
        Write-Host "ERROR: Invalid DNS server address format: $dns" -ForegroundColor Red
        exit 1
    }
}

if ($PrefixLength -lt 1 -or $PrefixLength -gt 32) {
    Write-Host "ERROR: Invalid prefix length: $PrefixLength (must be 1-32)" -ForegroundColor Red
    exit 1
}

# Get the adapter
$adapter = Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName }
if (-not $adapter) {
    Write-Host "ERROR: Adapter '$AdapterName' not found" -ForegroundColor Red
    Write-Host "`nAvailable adapters:" -ForegroundColor Yellow
    Get-NetAdapter | Format-Table Name, Status, InterfaceDescription -AutoSize
    exit 1
}

Write-Host "Validation passed!`n" -ForegroundColor Green

# Display current configuration
Write-Host "=== Current Configuration ===" -ForegroundColor Cyan
$currentIP = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex
Write-Host "Adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
Write-Host "Current IP: $($currentIP.IPv4Address.IPAddress)"
Write-Host "Current Gateway: $($currentIP.IPv4DefaultGateway.NextHop)"
$currentDNS = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
Write-Host "Current DNS: $($currentDNS.ServerAddresses -join ', ')"
Write-Host "DHCP Enabled: $($currentIP.NetIPv4Interface.Dhcp)"
Write-Host ""

# Confirm the change
Write-Host "=== New Configuration ===" -ForegroundColor Yellow
Write-Host "Adapter: $AdapterName"
Write-Host "IP Address: $IPAddress/$PrefixLength"
Write-Host "Gateway: $Gateway"
Write-Host "DNS Servers: $($DnsServers -join ', ')"
Write-Host "IPv6: Will be disabled (prevents IPv6 DNS preference)"
Write-Host ""

$confirmation = Read-Host "Apply this configuration? (yes/no)"
if ($confirmation -ne 'yes') {
    Write-Host "Aborted by user" -ForegroundColor Yellow
    exit 0
}

Write-Host "`nApplying static IP configuration..." -ForegroundColor Yellow

try {
    # Remove existing IP configuration
    Write-Host "Removing existing IP configuration..." -ForegroundColor Gray
    Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

    # Set new IP address
    Write-Host "Setting IP address: $IPAddress/$PrefixLength" -ForegroundColor Gray
    New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                     -IPAddress $IPAddress `
                     -PrefixLength $PrefixLength `
                     -DefaultGateway $Gateway | Out-Null

    Write-Host "  IP address configured" -ForegroundColor Green

    # Set DNS servers
    Write-Host "Setting DNS servers: $($DnsServers -join ', ')" -ForegroundColor Gray
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $DnsServers

    Write-Host "  DNS servers configured" -ForegroundColor Green

    # Disable IPv6 to prevent IPv6 DNS preference
    Write-Host "Disabling IPv6 on adapter..." -ForegroundColor Gray
    Disable-NetAdapterBinding -Name $AdapterName -ComponentID ms_tcpip6 -Confirm:$false
    Write-Host "  IPv6 disabled" -ForegroundColor Green

    # Flush DNS cache
    Clear-DnsClientCache
    Write-Host "  DNS cache flushed" -ForegroundColor Green

    # Wait a moment for changes to take effect
    Start-Sleep -Seconds 2

    # Verify configuration
    Write-Host "`n=== Verification ===" -ForegroundColor Cyan
    $newIP = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex
    $newDNS = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    $ipv6Binding = Get-NetAdapterBinding -Name $AdapterName -ComponentID ms_tcpip6

    Write-Host "Adapter: $($adapter.Name)"
    Write-Host "IP Address: $($newIP.IPv4Address.IPAddress)/$($newIP.IPv4Address.PrefixLength)" -ForegroundColor Green
    Write-Host "Gateway: $($newIP.IPv4DefaultGateway.NextHop)" -ForegroundColor Green
    Write-Host "DNS Servers: $($newDNS.ServerAddresses -join ', ')" -ForegroundColor Green
    Write-Host "DHCP Enabled: $($newIP.NetIPv4Interface.Dhcp)" -ForegroundColor $(if ($newIP.NetIPv4Interface.Dhcp -eq 'Disabled') { 'Green' } else { 'Yellow' })
    Write-Host "IPv6 Enabled: $($ipv6Binding.Enabled)" -ForegroundColor $(if ($ipv6Binding.Enabled -eq $false) { 'Green' } else { 'Yellow' })

    Write-Host "`nStatic IP configuration applied successfully!" -ForegroundColor Green
    Write-Host "This configuration will persist across reboots." -ForegroundColor Green

    # Test connectivity
    Write-Host "`n=== Connectivity Test ===" -ForegroundColor Cyan
    Write-Host "Testing gateway connectivity..."
    if (Test-Connection -ComputerName $Gateway -Count 2 -Quiet) {
        Write-Host "  Gateway is reachable" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Cannot reach gateway!" -ForegroundColor Red
    }

    Write-Host "Testing DNS server connectivity..."
    if (Test-Connection -ComputerName $DnsServers[0] -Count 2 -Quiet) {
        Write-Host "  DNS server is reachable" -ForegroundColor Green

        # Test DNS resolution
        try {
            Write-Host "Testing DNS resolution for 'pve.lab'..."
            $dnsTest = Resolve-DnsName -Name "pve.lab" -Server $DnsServers[0] -ErrorAction Stop
            Write-Host "  DNS resolution works: pve.lab -> $($dnsTest.IPAddress)" -ForegroundColor Green
        } catch {
            Write-Host "  WARNING: DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  WARNING: Cannot reach DNS server!" -ForegroundColor Red
    }

} catch {
    Write-Host "`nERROR: Failed to apply configuration" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nYou may need to revert to DHCP using Reset-DNS.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "`nConfiguration complete!`n" -ForegroundColor Green
