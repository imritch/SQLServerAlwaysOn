# Pre-Cluster Diagnostics
# Run on SQL01 to verify everything is ready for cluster creation
# This will help identify issues before attempting to create the cluster

$ErrorActionPreference = "Continue"

Write-Host "===== Pre-Cluster Diagnostics =====" -ForegroundColor Green
Write-Host ""

$Node1 = "SQL01.contoso.local"
$Node2 = "SQL02.contoso.local"
$AllPassed = $true

# Test 1: DNS Resolution
Write-Host "[1/10] Testing DNS Resolution..." -ForegroundColor Yellow
try {
    $dns1 = Resolve-DnsName $Node1 -ErrorAction Stop
    $dns2 = Resolve-DnsName $Node2 -ErrorAction Stop
    Write-Host "  ✓ $Node1 resolves to $($dns1.IPAddress)" -ForegroundColor Green
    Write-Host "  ✓ $Node2 resolves to $($dns2.IPAddress)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 2: Network Connectivity
Write-Host "[2/10] Testing Network Connectivity..." -ForegroundColor Yellow
$ping1 = Test-Connection -ComputerName $Node1 -Count 2 -Quiet
$ping2 = Test-Connection -ComputerName $Node2 -Count 2 -Quiet
if ($ping1 -and $ping2) {
    Write-Host "  ✓ Both nodes reachable via ping" -ForegroundColor Green
} else {
    Write-Host "  ✗ Ping failed" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 3: RPC Connectivity (Port 135)
Write-Host "[3/10] Testing RPC Connectivity (Port 135)..." -ForegroundColor Yellow
$rpc1 = Test-NetConnection -ComputerName $Node1 -Port 135 -WarningAction SilentlyContinue
$rpc2 = Test-NetConnection -ComputerName $Node2 -Port 135 -WarningAction SilentlyContinue
if ($rpc1.TcpTestSucceeded -and $rpc2.TcpTestSucceeded) {
    Write-Host "  ✓ RPC connectivity successful" -ForegroundColor Green
} else {
    Write-Host "  ✗ RPC connectivity failed (check security groups)" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 4: SMB Connectivity (Port 445)
Write-Host "[4/10] Testing SMB Connectivity (Port 445)..." -ForegroundColor Yellow
$smb1 = Test-NetConnection -ComputerName $Node1 -Port 445 -WarningAction SilentlyContinue
$smb2 = Test-NetConnection -ComputerName $Node2 -Port 445 -WarningAction SilentlyContinue
if ($smb1.TcpTestSucceeded -and $smb2.TcpTestSucceeded) {
    Write-Host "  ✓ SMB connectivity successful" -ForegroundColor Green
} else {
    Write-Host "  ✗ SMB connectivity failed (check security groups)" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 5: Domain Membership
Write-Host "[5/10] Checking Domain Membership..." -ForegroundColor Yellow
$domain1 = (Get-WmiObject -Class Win32_ComputerSystem -ComputerName $Node1).Domain
$domain2 = (Get-WmiObject -Class Win32_ComputerSystem -ComputerName $Node2).Domain
if ($domain1 -eq "contoso.local" -and $domain2 -eq "contoso.local") {
    Write-Host "  ✓ Both nodes in contoso.local domain" -ForegroundColor Green
} else {
    Write-Host "  ✗ Domain membership issue: $domain1, $domain2" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 6: Failover Clustering Feature
Write-Host "[6/10] Checking Failover Clustering Feature..." -ForegroundColor Yellow
$fc1 = Get-WindowsFeature -Name Failover-Clustering -ComputerName $Node1
$fc2 = Get-WindowsFeature -Name Failover-Clustering -ComputerName $Node2
if ($fc1.Installed -and $fc2.Installed) {
    Write-Host "  ✓ Failover Clustering installed on both nodes" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failover Clustering not installed" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 7: Windows Firewall Rules
Write-Host "[7/10] Checking Firewall Rules..." -ForegroundColor Yellow
$fwRules = Get-NetFirewallRule -DisplayGroup "Failover Clusters" | Where-Object {$_.Enabled -eq $true}
if ($fwRules.Count -gt 10) {
    Write-Host "  ✓ Firewall rules enabled ($($fwRules.Count) rules)" -ForegroundColor Green
} else {
    Write-Host "  ✗ Firewall rules not properly enabled" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Test 8: Network Adapter Configuration
Write-Host "[8/10] Checking Network Adapter Configuration..." -ForegroundColor Yellow
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Name -like "Ethernet*"} | Select-Object -First 1
$IPConfig = Get-NetIPConfiguration -InterfaceIndex $Adapter.InterfaceIndex
$IPs = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4
Write-Host "  Primary IP: $(($IPConfig.IPv4Address).IPAddress)" -ForegroundColor Cyan
Write-Host "  Total IPs configured: $($IPs.Count)" -ForegroundColor Cyan
if ($IPs.Count -eq 1) {
    Write-Host "  ✓ Only primary IP configured (correct for AWS clustering)" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Multiple IPs configured in Windows - should only have primary IP" -ForegroundColor Yellow
    $IPs | Select-Object IPAddress | Format-Table
}
Write-Host ""

# Test 9: Secondary IPs at ENI Level (check via EC2 metadata)
Write-Host "[9/10] Checking Secondary IPs at ENI Level..." -ForegroundColor Yellow
try {
    $mac = (Invoke-WebRequest -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs/ -UseBasicParsing).Content.Trim()
    $localIPs = (Invoke-WebRequest -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s" -UseBasicParsing).Content -split "`n"
    Write-Host "  IPs available at ENI level:" -ForegroundColor Cyan
    foreach ($ip in $localIPs) {
        if ($ip.Trim()) {
            Write-Host "    - $($ip.Trim())" -ForegroundColor White
        }
    }
    if ($localIPs.Count -ge 3) {
        Write-Host "  ✓ Secondary IPs assigned to ENI" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Not enough secondary IPs at ENI level" -ForegroundColor Red
        $AllPassed = $false
    }
} catch {
    Write-Host "  ⚠ Could not query EC2 metadata: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Test 10: WMI Connectivity
Write-Host "[10/10] Testing WMI Connectivity..." -ForegroundColor Yellow
try {
    $wmi1 = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Node1 -ErrorAction Stop
    $wmi2 = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Node2 -ErrorAction Stop
    Write-Host "  ✓ WMI connectivity to both nodes successful" -ForegroundColor Green
} catch {
    Write-Host "  ✗ WMI connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
    $AllPassed = $false
}
Write-Host ""

# Summary
Write-Host "===== Diagnostic Summary =====" -ForegroundColor Green
if ($AllPassed) {
    Write-Host "✓ All tests passed! You can proceed with cluster creation." -ForegroundColor Green
} else {
    Write-Host "✗ Some tests failed. Fix the issues above before creating the cluster." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Yellow
    Write-Host "1. Run add-security-group-rules.sh with correct VPC CIDR (10.0.0.0/16)" -ForegroundColor White
    Write-Host "2. Enable firewall rules on both nodes" -ForegroundColor White
    Write-Host "3. Verify secondary IPs assigned via 04b-Assign-Secondary-IPs.sh" -ForegroundColor White
    Write-Host "4. Remove secondary IPs from Windows using 04c-Cleanup-Secondary-IPs.ps1" -ForegroundColor White
}
Write-Host ""

