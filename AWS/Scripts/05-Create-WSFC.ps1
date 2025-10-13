# SQL01 - Create Windows Server Failover Cluster
# Run as CONTOSO\Administrator on SQL01 only

$ErrorActionPreference = "Stop"

$ClusterName = "SQLCLUSTER"
$Node1 = "SQL01"
$Node2 = "SQL02"
$ClusterIP = Read-Host "Enter unused IP for cluster in your subnet (e.g., 172.31.x.x)"

Write-Host "===== Creating Windows Server Failover Cluster =====" -ForegroundColor Green

# Step 1: Test Cluster Configuration
Write-Host "`n[1/3] Testing cluster configuration..." -ForegroundColor Yellow
Write-Host "This may take a few minutes..." -ForegroundColor Cyan

$TestResult = Test-Cluster -Node $Node1, $Node2

if ($TestResult) {
    Write-Host "Cluster validation complete. Check C:\Windows\Cluster\Reports for results." -ForegroundColor Green
} else {
    Write-Host "WARNING: Cluster validation had issues. Continuing anyway..." -ForegroundColor Yellow
}

# Step 2: Create Cluster (No Storage)
Write-Host "`n[2/3] Creating failover cluster..." -ForegroundColor Yellow
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Nodes: $Node1, $Node2" -ForegroundColor Cyan
Write-Host "Note: Using NoStorage for SQL AG" -ForegroundColor Cyan

New-Cluster -Name $ClusterName `
    -Node $Node1, $Node2 `
    -NoStorage `
    -StaticAddress $ClusterIP `
    -Force

Write-Host "Cluster created successfully!" -ForegroundColor Green

# Step 3: Configure Cluster Quorum (Cloud Witness recommended for AWS)
Write-Host "`n[3/3] Configuring cluster quorum..." -ForegroundColor Yellow
Write-Host "Using Node Majority (for demo)" -ForegroundColor Cyan

# For demo: Node Majority (works for 2 nodes but not ideal)
Set-ClusterQuorum -NodeMajority

Write-Host "`nQuorum configured!" -ForegroundColor Green
Write-Host "`nPRODUCTION NOTE: Use AWS S3 for cloud witness in production." -ForegroundColor Yellow

# Summary
Write-Host "`n===== WSFC Creation Complete =====" -ForegroundColor Green
Write-Host "`nCluster Details:" -ForegroundColor Cyan
Get-Cluster | Format-List Name, Domain

Write-Host "`nCluster Nodes:" -ForegroundColor Cyan
Get-ClusterNode | Format-Table Name, State, ID -AutoSize

Write-Host "`nNext: Install SQL Server on both nodes" -ForegroundColor Yellow

