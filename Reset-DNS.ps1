#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Reset DNS configuration to automatic (DHCP) on Windows 11 network adapter(s).

.DESCRIPTION
    Resets DNS server addresses to obtain automatically from DHCP on specified or active network adapters.
    Also re-enables IPv6 if it was previously disabled.

.PARAMETER AdapterName
    Name of the network adapter to reset. If not specified, resets all active adapters.

.EXAMPLE
    .\Reset-DNS.ps1
    Resets DNS to automatic on all active adapters.

.EXAMPLE
    .\Reset-DNS.ps1 -AdapterName "Ethernet"
    Resets DNS to automatic on the Ethernet adapter only.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$AdapterName
)

function Reset-DnsServerForAdapter {
    param(
        [Parameter(Mandatory=$true)]
        $Adapter
    )

    Write-Host "Resetting adapter: $($Adapter.Name) ($($Adapter.InterfaceDescription))" -ForegroundColor Cyan
    Write-Host "  Status: $($Adapter.Status)" -ForegroundColor Gray

    # Show current DNS before reset
    $currentDns = Get-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4
    $ipv6Binding = Get-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6
    if ($currentDns.ServerAddresses) {
        Write-Host "  Current DNS: $($currentDns.ServerAddresses -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "  Current DNS: Automatic (DHCP)" -ForegroundColor Gray
    }
    Write-Host "  IPv6 Enabled: $($ipv6Binding.Enabled)" -ForegroundColor Gray

    try {
        # Reset to automatic (DHCP)
        Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ResetServerAddresses

        Write-Host "  DNS reset to automatic (DHCP)" -ForegroundColor Green

        # Re-enable IPv6 if it was disabled
        if (-not $ipv6Binding.Enabled) {
            Write-Host "  Re-enabling IPv6..." -ForegroundColor Gray
            Enable-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6
            Write-Host "  IPv6 re-enabled" -ForegroundColor Green
        } else {
            Write-Host "  IPv6 already enabled" -ForegroundColor Gray
        }

        # Flush DNS cache
        Clear-DnsClientCache
        Write-Host "  DNS cache flushed" -ForegroundColor Green

        # Release and renew DHCP to get fresh DNS info
        Write-Host "  Renewing DHCP lease..." -ForegroundColor Gray
        ipconfig /release $Adapter.Name 2>&1 | Out-Null
        ipconfig /renew $Adapter.Name 2>&1 | Out-Null

        # Show new DNS settings (may take a moment to populate)
        Start-Sleep -Milliseconds 500
        $newDns = Get-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4
        if ($newDns.ServerAddresses) {
            Write-Host "  New DNS from DHCP: $($newDns.ServerAddresses -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "  New DNS: Automatic (DHCP) - waiting for lease" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "  ERROR: Failed to reset DNS - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
Write-Host "`nResetting DNS to Automatic (DHCP)" -ForegroundColor Yellow
Write-Host "=================================`n" -ForegroundColor Yellow

# Get network adapters
if ($AdapterName) {
    $adapters = Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName }
    if (-not $adapters) {
        Write-Host "ERROR: Adapter '$AdapterName' not found" -ForegroundColor Red
        Write-Host "`nAvailable adapters:" -ForegroundColor Yellow
        Get-NetAdapter | Format-Table Name, Status, InterfaceDescription -AutoSize
        exit 1
    }
} else {
    # Get all Up adapters (connected)
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    if (-not $adapters) {
        Write-Host "ERROR: No active network adapters found" -ForegroundColor Red
        exit 1
    }
    Write-Host "Resetting all active adapters to automatic DNS`n" -ForegroundColor Yellow
}

# Reset each adapter
foreach ($adapter in $adapters) {
    Reset-DnsServerForAdapter -Adapter $adapter
    Write-Host ""
}

Write-Host "DNS reset complete!`n" -ForegroundColor Green

# Show final DNS configuration
Write-Host "Current DNS Configuration:" -ForegroundColor Yellow
Write-Host "=========================`n" -ForegroundColor Yellow
foreach ($adapter in $adapters) {
    $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    $ipv6Status = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6
    Write-Host "$($adapter.Name):" -ForegroundColor Cyan
    if ($dnsConfig.ServerAddresses) {
        Write-Host "  DNS: $($dnsConfig.ServerAddresses -join ', ')" -ForegroundColor White
    } else {
        Write-Host "  DNS: Automatic (DHCP)" -ForegroundColor White
    }
    Write-Host "  IPv6: $($ipv6Status.Enabled)" -ForegroundColor White
}
