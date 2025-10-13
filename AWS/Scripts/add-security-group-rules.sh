#!/bin/bash
# Add missing security group rules for Active Directory and SQL AG
# Run this from WSL/Linux terminal if you already deployed the stack

set -e

# Configuration
STACK_NAME="${1:-sql-ag-demo}"
REGION="${2:-us-east-1}"

echo "===== Adding Security Group Rules ====="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Get security group name from CloudFormation
echo "[1/3] Getting security group..."
SG_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' \
  --output text)

if [ -z "$SG_NAME" ]; then
  echo "ERROR: Could not find security group in stack outputs"
  exit 1
fi

echo "Security Group Name: $SG_NAME"

# Get actual security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --region "$REGION" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

echo "Security Group ID: $SG_ID"
echo ""

# Function to add rule with error handling
add_rule() {
  local protocol=$1
  local port=$2
  local cidr=$3
  local description=$4
  
  echo "Adding: $description ($protocol/$port)"
  
  if aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol "$protocol" \
    --port "$port" \
    --cidr "$cidr" \
    --region "$REGION" 2>/dev/null; then
    echo "  ✓ Added"
  else
    echo "  - Already exists or error (continuing...)"
  fi
}

echo "[2/3] Adding DNS rules..."
add_rule tcp 53 172.31.0.0/16 "DNS TCP"
add_rule udp 53 172.31.0.0/16 "DNS UDP"

echo ""
echo "[3/3] Adding Active Directory rules..."
add_rule tcp 88 172.31.0.0/16 "Kerberos TCP"
add_rule udp 88 172.31.0.0/16 "Kerberos UDP"
add_rule tcp 389 172.31.0.0/16 "LDAP"
add_rule udp 389 172.31.0.0/16 "LDAP UDP"
add_rule tcp 636 172.31.0.0/16 "LDAPS"
add_rule tcp 3268-3269 172.31.0.0/16 "Global Catalog"
add_rule tcp 445 172.31.0.0/16 "SMB"
add_rule tcp 135 172.31.0.0/16 "RPC"
add_rule tcp 49152-65535 172.31.0.0/16 "Dynamic RPC"

echo ""
echo "===== Security Group Rules Added Successfully! ====="
echo ""
echo "You can now:"
echo "1. Test DNS from SQL nodes: nslookup contoso.local <DC_IP>"
echo "2. Join SQL nodes to domain: Run 03-Join-Domain.ps1"
echo ""

