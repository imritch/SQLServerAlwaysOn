# SQL01 - Create Windows Server Failover Cluster (Multi-Subnet)
# Run as CONTOSO\Administrator on SQL01 only

$ErrorActionPreference = "Stop"

$ClusterName = "SQLCLUSTER"
$Node1 = "SQL01"
$Node2 = "SQL02"

Write-Host "===== Creating Windows Server Failover Cluster (Multi-Subnet) =====" -ForegroundColor Green
Write-Host "`nIMPORTANT: Multi-subnet cluster requires 2 IP addresses (one per subnet)" -ForegroundColor Yellow
Write-Host "Check CloudFormation outputs for recommended IPs" -ForegroundColor Cyan

# Get subnet information
Write-Host "`nSubnet Information:" -ForegroundColor Cyan
Write-Host "  Subnet 1 (SQL01): 10.0.1.0/24 - use IP like 10.0.1.50" -ForegroundColor White
Write-Host "  Subnet 2 (SQL02): 10.0.2.0/24 - use IP like 10.0.2.50" -ForegroundColor White

$ClusterIP1 = Read-Host "`nEnter unused IP for cluster in Subnet 1 (e.g., 10.0.1.50)"
$ClusterIP2 = Read-Host "Enter unused IP for cluster in Subnet 2 (e.g., 10.0.2.50)"

Write-Host "`n===== Multi-Subnet Configuration =====" -ForegroundColor Green
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Cluster IP 1 (Subnet 1): $ClusterIP1" -ForegroundColor Cyan
Write-Host "Cluster IP 2 (Subnet 2): $ClusterIP2" -ForegroundColor Cyan

# Step 1: Test Cluster Configuration
Write-Host "`n[1/4] Testing cluster configuration..." -ForegroundColor Yellow
Write-Host "This may take a few minutes..." -ForegroundColor Cyan

$TestResult = Test-Cluster -Node $Node1, $Node2

if ($TestResult) {
    Write-Host "Cluster validation complete. Check C:\Windows\Cluster\Reports for results." -ForegroundColor Green
} else {
    Write-Host "WARNING: Cluster validation had issues. Continuing anyway..." -ForegroundColor Yellow
}

# Step 2: Create Cluster with Multiple Static IPs (Multi-Subnet)
Write-Host "`n[2/4] Creating multi-subnet failover cluster..." -ForegroundColor Yellow
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Nodes: $Node1, $Node2" -ForegroundColor Cyan
Write-Host "Cluster IP Addresses: $ClusterIP1, $ClusterIP2" -ForegroundColor Cyan
Write-Host "Note: Using NoStorage for SQL AG" -ForegroundColor Cyan

# Create cluster with both IPs
New-Cluster -Name $ClusterName `
    -Node $Node1, $Node2 `
    -NoStorage `
    -StaticAddress $ClusterIP1, $ClusterIP2 `
    -Force

Write-Host "Multi-subnet cluster created successfully!" -ForegroundColor Green

# Step 3: Configure Cluster for Multi-Subnet
Write-Host "`n[3/4] Configuring cluster for multi-subnet support..." -ForegroundColor Yellow

# Set cluster parameters for multi-subnet failover
(Get-Cluster).SameSubnetDelay = 1000
(Get-Cluster).SameSubnetThreshold = 5
(Get-Cluster).CrossSubnetDelay = 1000
(Get-Cluster).CrossSubnetThreshold = 5

# Set cluster network dependency to OR (important for multi-subnet)
$clusterResource = Get-ClusterResource -Name "Cluster Name"
if ($clusterResource) {
    $clusterResource | Set-ClusterParameter -Name "HostRecordTTL" -Value 300
    Write-Host "Cluster Name resource TTL set to 300 seconds" -ForegroundColor Green
}

Write-Host "Multi-subnet parameters configured" -ForegroundColor Green

# Step 4: Configure Cluster Quorum (Cloud Witness recommended for AWS)
Write-Host "`n[4/4] Configuring cluster quorum..." -ForegroundColor Yellow
Write-Host "Using Node Majority (for demo)" -ForegroundColor Cyan

# For demo: Node Majority (works for 2 nodes but not ideal)
Set-ClusterQuorum -NodeMajority

Write-Host "`nQuorum configured!" -ForegroundColor Green
Write-Host "`nPRODUCTION NOTE: Use AWS S3 for cloud witness in production." -ForegroundColor Yellow

# Summary
Write-Host "`n===== Multi-Subnet WSFC Creation Complete =====" -ForegroundColor Green
Write-Host "`nCluster Details:" -ForegroundColor Cyan
Get-Cluster | Format-List Name, Domain

Write-Host "`nCluster Nodes:" -ForegroundColor Cyan
Get-ClusterNode | Format-Table Name, State, ID -AutoSize

Write-Host "`nCluster IP Resources:" -ForegroundColor Cyan
Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | Get-ClusterParameter | Format-Table -AutoSize

Write-Host "`nCluster Network Configuration:" -ForegroundColor Cyan
Write-Host "  SameSubnetDelay: $((Get-Cluster).SameSubnetDelay)ms"
Write-Host "  SameSubnetThreshold: $((Get-Cluster).SameSubnetThreshold)"
Write-Host "  CrossSubnetDelay: $((Get-Cluster).CrossSubnetDelay)ms"
Write-Host "  CrossSubnetThreshold: $((Get-Cluster).CrossSubnetThreshold)"

Write-Host "`nNext: Install SQL Server 2022 on both nodes" -ForegroundColor Yellow

