# SQL01 - Create Availability Group
# Run as CONTOSO\Administrator on SQL01

$ErrorActionPreference = "Stop"

# Import SQL PowerShell module
Import-Module SqlServer

# Configuration
$AGName = "SQLAOAG01"
$ListenerName = "SQLAGL01"
$ListenerIP = Read-Host "Enter unused IP for AG Listener (e.g., 172.31.x.x)"
$ListenerPort = 59999
$EndpointPort = 5022
$DatabaseName = "AGTestDB"
$PrimaryReplica = "SQL01"
$SecondaryReplica = "SQL02"

Write-Host "===== Creating Availability Group =====" -ForegroundColor Green

# Step 1: Create Database Mirroring Endpoints on both replicas
Write-Host "`n[1/6] Creating database mirroring endpoints..." -ForegroundColor Yellow

# SQL01 Endpoint
$endpoint1Script = @"
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT Hadr_endpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = $EndpointPort)
    FOR DATABASE_MIRRORING (ROLE = ALL);
END
GO

GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [CONTOSO\sqlsvc$];
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $endpoint1Script
Write-Host "Endpoint created on $PrimaryReplica" -ForegroundColor Green

# SQL02 Endpoint
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $endpoint1Script
Write-Host "Endpoint created on $SecondaryReplica" -ForegroundColor Green

# Step 2: Share backup folder on SQL01
Write-Host "`n[2/6] Setting up backup share..." -ForegroundColor Yellow
$backupPath = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\BACKUP"
$shareName = "SQLBackup"

try {
    New-SmbShare -Name $shareName -Path $backupPath -FullAccess "Everyone" -ErrorAction SilentlyContinue
    Write-Host "Backup share created: \\$PrimaryReplica\$shareName" -ForegroundColor Green
} catch {
    Write-Host "Share may already exist" -ForegroundColor Yellow
}

# Step 3: Create Availability Group on Primary
Write-Host "`n[3/6] Creating Availability Group on primary replica..." -ForegroundColor Yellow

$createAGScript = @"
CREATE AVAILABILITY GROUP [$AGName]
WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY)
FOR DATABASE [$DatabaseName]
REPLICA ON 
    N'$PrimaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$PrimaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    ),
    N'$SecondaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$SecondaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    );
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createAGScript
Write-Host "Availability Group '$AGName' created on $PrimaryReplica" -ForegroundColor Green

# Step 4: Join Secondary Replica
Write-Host "`n[4/6] Joining secondary replica to AG..." -ForegroundColor Yellow

$joinAGScript = "ALTER AVAILABILITY GROUP [$AGName] JOIN;"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinAGScript
Write-Host "$SecondaryReplica joined to AG" -ForegroundColor Green

# Step 5: Restore database on Secondary
Write-Host "`n[5/6] Restoring database on secondary replica..." -ForegroundColor Yellow

$uncBackupPath = "\\$PrimaryReplica\$shareName"

Write-Host "Restoring full backup..." -ForegroundColor Cyan
$restoreFullScript = @"
RESTORE DATABASE [$DatabaseName]
FROM DISK = N'$uncBackupPath\AGTestDB_Full.bak'
WITH NORECOVERY, REPLACE;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreFullScript

Write-Host "Restoring log backup..." -ForegroundColor Cyan
$restoreLogScript = @"
RESTORE LOG [$DatabaseName]
FROM DISK = N'$uncBackupPath\AGTestDB_Log.trn'
WITH NORECOVERY;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreLogScript

# Join database to AG on secondary
Write-Host "Joining database to AG on secondary..." -ForegroundColor Cyan
$joinDBScript = "ALTER DATABASE [$DatabaseName] SET HADR AVAILABILITY GROUP = [$AGName];"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinDBScript

Write-Host "Database joined to AG on $SecondaryReplica" -ForegroundColor Green

# Step 6: Create AG Listener
Write-Host "`n[6/6] Creating Availability Group Listener..." -ForegroundColor Yellow

$createListenerScript = @"
ALTER AVAILABILITY GROUP [$AGName]
ADD LISTENER N'$ListenerName' (
    WITH IP ((N'$ListenerIP', N'255.255.255.0')),
    PORT = $ListenerPort
);
GO
"@

try {
    Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createListenerScript
    Write-Host "Listener '$ListenerName' created" -ForegroundColor Green
} catch {
    Write-Host "Error creating listener: $_" -ForegroundColor Red
    Write-Host "You may need to create it manually in SSMS" -ForegroundColor Yellow
}

# Summary
Write-Host "`n===== Availability Group Creation Complete! =====" -ForegroundColor Green
Write-Host "`nAG Details:" -ForegroundColor Cyan
Write-Host "  AG Name: $AGName"
Write-Host "  Listener: $ListenerName"
Write-Host "  Listener IP: $ListenerIP"
Write-Host "  Listener Port: $ListenerPort"
Write-Host "  Primary: $PrimaryReplica"
Write-Host "  Secondary: $SecondaryReplica"
Write-Host "  Database: $DatabaseName"

Write-Host "`nTest connection string:" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName,$ListenerPort;Database=$DatabaseName;Integrated Security=True;MultiSubnetFailover=True;" -ForegroundColor Cyan

Write-Host "`nNext: Run validation script (10-Validate-AG.sql)" -ForegroundColor Yellow

