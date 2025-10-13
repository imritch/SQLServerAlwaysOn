# DC01 - Update gMSA Permissions After Domain Join
# Run as CONTOSO\Administrator AFTER SQL01 and SQL02 have joined the domain

$ErrorActionPreference = "Stop"

Write-Host "===== Updating gMSA Permissions =====" -ForegroundColor Green

# Check if SQL servers have joined domain
Write-Host "`nChecking if SQL servers are in domain..." -ForegroundColor Yellow

$sql01Computer = Get-ADComputer -Filter {Name -eq "SQL01"} -ErrorAction SilentlyContinue
$sql02Computer = Get-ADComputer -Filter {Name -eq "SQL02"} -ErrorAction SilentlyContinue

if (-not $sql01Computer) {
    Write-Host "WARNING: SQL01 has not joined the domain yet!" -ForegroundColor Red
    Write-Host "Run this script after SQL01 and SQL02 join the domain." -ForegroundColor Yellow
    exit
}

if (-not $sql02Computer) {
    Write-Host "WARNING: SQL02 has not joined the domain yet!" -ForegroundColor Red
    Write-Host "Run this script after SQL01 and SQL02 join the domain." -ForegroundColor Yellow
    exit
}

Write-Host "SQL01: Found in domain" -ForegroundColor Green
Write-Host "SQL02: Found in domain" -ForegroundColor Green

# Update SQL Service gMSA
Write-Host "`n[1/2] Updating SQL Service gMSA permissions..." -ForegroundColor Yellow

try {
    Set-ADServiceAccount -Identity "sqlsvc" `
        -PrincipalsAllowedToRetrieveManagedPassword "SQL01$", "SQL02$"
    
    Write-Host "Updated sqlsvc permissions" -ForegroundColor Green
    Write-Host "Allowed principals: SQL01$, SQL02$" -ForegroundColor Cyan
} catch {
    Write-Host "Error updating sqlsvc: $_" -ForegroundColor Red
}

# Update SQL Agent gMSA
Write-Host "`n[2/2] Updating SQL Agent gMSA permissions..." -ForegroundColor Yellow

try {
    Set-ADServiceAccount -Identity "sqlagent" `
        -PrincipalsAllowedToRetrieveManagedPassword "SQL01$", "SQL02$"
    
    Write-Host "Updated sqlagent permissions" -ForegroundColor Green
    Write-Host "Allowed principals: SQL01$, SQL02$" -ForegroundColor Cyan
} catch {
    Write-Host "Error updating sqlagent: $_" -ForegroundColor Red
}

# Verify
Write-Host "`n===== Verification =====" -ForegroundColor Green

$sqlsvcPrincipals = (Get-ADServiceAccount -Identity "sqlsvc" -Properties PrincipalsAllowedToRetrieveManagedPassword).PrincipalsAllowedToRetrieveManagedPassword
$sqlagentPrincipals = (Get-ADServiceAccount -Identity "sqlagent" -Properties PrincipalsAllowedToRetrieveManagedPassword).PrincipalsAllowedToRetrieveManagedPassword

Write-Host "`nsqlsvc principals:" -ForegroundColor Cyan
$sqlsvcPrincipals | ForEach-Object { Write-Host "  - $_" }

Write-Host "`nsqlagent principals:" -ForegroundColor Cyan
$sqlagentPrincipals | ForEach-Object { Write-Host "  - $_" }

Write-Host "`n===== gMSA Permissions Updated Successfully! =====" -ForegroundColor Green
Write-Host "Next: Install SQL Server on SQL01 and SQL02" -ForegroundColor Yellow

