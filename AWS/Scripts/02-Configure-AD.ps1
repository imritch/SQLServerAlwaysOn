# DC01 - Configure Active Directory for SQL AG
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

$DomainName = "contoso.local"
$DomainDN = "DC=contoso,DC=local"

Write-Host "===== Configuring Active Directory =====" -ForegroundColor Green

# Step 1: Create OUs
Write-Host "`n[1/5] Creating Organizational Units..." -ForegroundColor Yellow

$OUs = @("Servers", "ServiceAccounts", "SQLServers")
foreach ($OU in $OUs) {
    try {
        New-ADOrganizationalUnit -Name $OU -Path $DomainDN -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU: $OU" -ForegroundColor Green
    } catch {
        Write-Host "OU $OU may already exist: $_" -ForegroundColor Yellow
    }
}

# Step 2: Create KDS Root Key for gMSA
Write-Host "`n[2/5] Creating KDS Root Key for gMSA..." -ForegroundColor Yellow
Write-Host "Note: In production, this takes 10 hours to replicate. We're forcing immediate availability." -ForegroundColor Cyan

try {
    # Check if key already exists
    $existingKey = Get-KdsRootKey
    if ($existingKey) {
        Write-Host "KDS Root Key already exists" -ForegroundColor Yellow
    } else {
        # For lab/demo: EffectiveTime 10 hours ago (makes it immediately usable)
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
        Write-Host "KDS Root Key created successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "Error creating KDS Root Key: $_" -ForegroundColor Red
}

# Step 3: Create SQL Service gMSA (without principals - will add after domain join)
Write-Host "`n[3/5] Creating gMSA for SQL Server Service..." -ForegroundColor Yellow

$gMSAName = "sqlsvc"
$gMSADNSHostName = "$gMSAName.$DomainName"

try {
    $existingGMSA = Get-ADServiceAccount -Filter {Name -eq $gMSAName} -ErrorAction SilentlyContinue
    if ($existingGMSA) {
        Write-Host "gMSA '$gMSAName' already exists" -ForegroundColor Yellow
    } else {
        # Create without principals first (SQL servers not joined yet)
        New-ADServiceAccount -Name $gMSAName `
            -DNSHostName $gMSADNSHostName `
            -Path "OU=ServiceAccounts,$DomainDN" `
            -Enabled $true
        
        Write-Host "gMSA '$gMSAName' created successfully" -ForegroundColor Green
        Write-Host "NOTE: Principals will be added after SQL servers join domain" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error creating gMSA: $_" -ForegroundColor Red
}

# Step 4: Create SQL Agent gMSA (without principals - will add after domain join)
Write-Host "`n[4/5] Creating gMSA for SQL Server Agent..." -ForegroundColor Yellow

$gMSAAgentName = "sqlagent"
$gMSAAgentDNSHostName = "$gMSAAgentName.$DomainName"

try {
    $existingGMSA = Get-ADServiceAccount -Filter {Name -eq $gMSAAgentName} -ErrorAction SilentlyContinue
    if ($existingGMSA) {
        Write-Host "gMSA '$gMSAAgentName' already exists" -ForegroundColor Yellow
    } else {
        # Create without principals first (SQL servers not joined yet)
        New-ADServiceAccount -Name $gMSAAgentName `
            -DNSHostName $gMSAAgentDNSHostName `
            -Path "OU=ServiceAccounts,$DomainDN" `
            -Enabled $true
        
        Write-Host "gMSA '$gMSAAgentName' created successfully" -ForegroundColor Green
        Write-Host "NOTE: Principals will be added after SQL servers join domain" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error creating gMSA: $_" -ForegroundColor Red
}

# Step 5: Create SQL Admin User
Write-Host "`n[5/5] Creating SQL Admin user..." -ForegroundColor Yellow

$SqlAdminUser = "sqladmin"
$SqlAdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

try {
    New-ADUser -Name $SqlAdminUser `
        -AccountPassword $SqlAdminPassword `
        -Path "OU=ServiceAccounts,$DomainDN" `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $false
    
    # Add to Domain Admins (for installation purposes)
    Add-ADGroupMember -Identity "Domain Admins" -Members $SqlAdminUser
    
    Write-Host "SQL Admin user created: $SqlAdminUser" -ForegroundColor Green
    Write-Host "Password: P@ssw0rd123!" -ForegroundColor Cyan
} catch {
    Write-Host "SQL Admin user may already exist: $_" -ForegroundColor Yellow
}

# Summary
Write-Host "`n===== Active Directory Configuration Complete =====" -ForegroundColor Green
Write-Host "`nCreated Resources:" -ForegroundColor Cyan
Write-Host "  - gMSA: CONTOSO\$gMSAName$ (SQL Service)"
Write-Host "  - gMSA: CONTOSO\$gMSAAgentName$ (SQL Agent)"
Write-Host "  - User: CONTOSO\$SqlAdminUser (Password: P@ssw0rd123!)"
Write-Host "`nNext: Join SQL01 and SQL02 to the domain" -ForegroundColor Yellow

