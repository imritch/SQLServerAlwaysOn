# SQL01 - Create Availability Group (Multi-Subnet)
# Run as CONTOSO\Administrator on SQL01

$ErrorActionPreference = "Stop"

# Import SQL PowerShell module
Import-Module SqlServer

# Configuration
$AGName = "SQLAOAG01"
$ListenerName = "SQLAGL01"
$ListenerPort = 59999
$EndpointPort = 5022
$DatabaseName = "AGTestDB"
$PrimaryReplica = "SQL01"
$SecondaryReplica = "SQL02"

Write-Host "===== Creating Availability Group (Multi-Subnet) =====" -ForegroundColor Green
Write-Host "`nIMPORTANT: Multi-subnet AG Listener requires 2 IP addresses (one per subnet)" -ForegroundColor Yellow
Write-Host "Check CloudFormation outputs for recommended IPs" -ForegroundColor Cyan

# Get subnet information
Write-Host "`nSubnet Information:" -ForegroundColor Cyan
Write-Host "  Subnet 1 (SQL01): 10.0.1.0/24" -ForegroundColor White
Write-Host "  Subnet 2 (SQL02): 10.0.2.0/24" -ForegroundColor White
Write-Host "`nPre-assigned Secondary IPs for Listener:" -ForegroundColor Yellow
Write-Host "  Listener IP 1: 10.0.1.51" -ForegroundColor White
Write-Host "  Listener IP 2: 10.0.2.51" -ForegroundColor White
Write-Host "`n(These were assigned in step 04b and configured in step 04c)" -ForegroundColor Cyan

$ListenerIP1 = Read-Host "`nEnter AG Listener IP for Subnet 1 (press Enter for 10.0.1.51)"
if ([string]::IsNullOrWhiteSpace($ListenerIP1)) {
    $ListenerIP1 = "10.0.1.51"
}

$ListenerIP2 = Read-Host "Enter AG Listener IP for Subnet 2 (press Enter for 10.0.2.51)"
if ([string]::IsNullOrWhiteSpace($ListenerIP2)) {
    $ListenerIP2 = "10.0.2.51"
}

Write-Host "`n===== Multi-Subnet AG Configuration =====" -ForegroundColor Green
Write-Host "AG Name: $AGName" -ForegroundColor Cyan
Write-Host "Listener Name: $ListenerName" -ForegroundColor Cyan
Write-Host "Listener IP 1 (Subnet 1): $ListenerIP1" -ForegroundColor Cyan
Write-Host "Listener IP 2 (Subnet 2): $ListenerIP2" -ForegroundColor Cyan
Write-Host "Listener Port: $ListenerPort" -ForegroundColor Cyan

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
# SQL Server 2022 uses MSSQL16
$backupPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP"
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

# Step 6: Create AG Listener (Multi-Subnet with 2 IPs)
Write-Host "`n[6/6] Creating Availability Group Listener (Multi-Subnet)..." -ForegroundColor Yellow

$createListenerScript = @"
ALTER AVAILABILITY GROUP [$AGName]
ADD LISTENER N'$ListenerName' (
    WITH IP (
        (N'$ListenerIP1', N'255.255.255.0'),
        (N'$ListenerIP2', N'255.255.255.0')
    ),
    PORT = $ListenerPort
);
GO
"@

Write-Host "Creating listener with IPs: $ListenerIP1, $ListenerIP2" -ForegroundColor Cyan

try {
    Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createListenerScript -QueryTimeout 120
    Write-Host "Multi-subnet listener '$ListenerName' created successfully" -ForegroundColor Green
    
    # Wait for listener to come online
    Start-Sleep -Seconds 5
    
    # Verify listener is online
    $listenerCheck = @"
SELECT 
    dns_name,
    port,
    ip_configuration_string_from_cluster
FROM sys.availability_group_listeners
WHERE dns_name = N'$ListenerName';
"@
    
    $listenerInfo = Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $listenerCheck
    if ($listenerInfo) {
        Write-Host "Listener is online and registered" -ForegroundColor Green
    }
} catch {
    Write-Host "Error creating listener: $_" -ForegroundColor Red
    Write-Host "You may need to create it manually in SSMS or check IP availability" -ForegroundColor Yellow
}

# Summary
Write-Host "`n===== Multi-Subnet Availability Group Creation Complete! =====" -ForegroundColor Green
Write-Host "`nAG Details:" -ForegroundColor Cyan
Write-Host "  AG Name: $AGName"
Write-Host "  Listener: $ListenerName"
Write-Host "  Listener IP 1 (Subnet 1): $ListenerIP1"
Write-Host "  Listener IP 2 (Subnet 2): $ListenerIP2"
Write-Host "  Listener Port: $ListenerPort"
Write-Host "  Primary: $PrimaryReplica (Subnet 1)"
Write-Host "  Secondary: $SecondaryReplica (Subnet 2)"
Write-Host "  Database: $DatabaseName"
Write-Host "  SQL Server Version: 2022"

Write-Host "`nTest connection string (REQUIRED: MultiSubnetFailover=True):" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName,$ListenerPort;Database=$DatabaseName;Integrated Security=True;MultiSubnetFailover=True;" -ForegroundColor Cyan

Write-Host "`nConnection via listener DNS:" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName.contoso.local,$ListenerPort;Database=$DatabaseName;Integrated Security=True;MultiSubnetFailover=True;" -ForegroundColor Cyan

Write-Host "`nIMPORTANT: Always use MultiSubnetFailover=True for multi-subnet AG connections!" -ForegroundColor Red

Write-Host "`nNext: Run validation script (10-Validate-AG.sql)" -ForegroundColor Yellow

