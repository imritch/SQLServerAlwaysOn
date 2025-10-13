# SQL01/SQL02 - Install Failover Clustering Feature
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

Write-Host "===== Installing Failover Clustering =====" -ForegroundColor Green

# Install Failover Clustering with Management Tools
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools

Write-Host "`nFailover Clustering installed successfully!" -ForegroundColor Green
Write-Host "Reboot recommended but not required." -ForegroundColor Yellow
Write-Host "`nNext: Run this on both SQL01 and SQL02, then create the cluster from SQL01" -ForegroundColor Cyan

