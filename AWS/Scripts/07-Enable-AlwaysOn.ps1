# SQL01/SQL02 - Enable AlwaysOn High Availability
# Run as Administrator after SQL Server is installed

$ErrorActionPreference = "Stop"

Write-Host "===== Enabling AlwaysOn High Availability =====" -ForegroundColor Green

try {
    # Import SQL PowerShell module
    Import-Module SqlServer -ErrorAction SilentlyContinue
    
    # Enable AlwaysOn
    Enable-SqlAlwaysOn -ServerInstance $env:COMPUTERNAME -Force
    
    Write-Host "AlwaysOn enabled successfully!" -ForegroundColor Green
    
    # Restart SQL Service
    Write-Host "Restarting SQL Server service..." -ForegroundColor Yellow
    Restart-Service MSSQLSERVER -Force
    
    Write-Host "SQL Service restarted!" -ForegroundColor Green
    
} catch {
    Write-Host "Error enabling AlwaysOn: $_" -ForegroundColor Red
    Write-Host "`nManual steps:" -ForegroundColor Yellow
    Write-Host "1. Open SQL Server Configuration Manager" -ForegroundColor Cyan
    Write-Host "2. Right-click SQL Server (MSSQLSERVER) -> Properties" -ForegroundColor Cyan
    Write-Host "3. Go to AlwaysOn High Availability tab" -ForegroundColor Cyan
    Write-Host "4. Check 'Enable AlwaysOn Availability Groups'" -ForegroundColor Cyan
    Write-Host "5. Click OK and restart SQL Server service" -ForegroundColor Cyan
}

Write-Host "`n===== AlwaysOn Configuration Complete =====" -ForegroundColor Green
Write-Host "Run this script on both SQL01 and SQL02" -ForegroundColor Yellow
Write-Host "Next: Create sample database and Availability Group from SQL01" -ForegroundColor Yellow

