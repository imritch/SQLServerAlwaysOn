#!/bin/bash
# Add missing security group rules for Active Directory and SQL AG
# Run this from WSL/Linux terminal if you already deployed the stack

set -e

# Configuration
STACK_NAME="${1:-sql-ag-demo}"
REGION="${2:-us-east-1}"
VPC_CIDR="${3:-10.0.0.0/16}"

echo "===== Adding Security Group Rules ====="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo "VPC CIDR: $VPC_CIDR"
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
add_rule tcp 53 "$VPC_CIDR" "DNS TCP"
add_rule udp 53 "$VPC_CIDR" "DNS UDP"

echo ""
echo "[3/3] Adding Active Directory and Clustering rules..."
add_rule tcp 88 "$VPC_CIDR" "Kerberos TCP"
add_rule udp 88 "$VPC_CIDR" "Kerberos UDP"
add_rule tcp 389 "$VPC_CIDR" "LDAP"
add_rule udp 389 "$VPC_CIDR" "LDAP UDP"
add_rule tcp 636 "$VPC_CIDR" "LDAPS"
add_rule tcp 3268-3269 "$VPC_CIDR" "Global Catalog"
add_rule tcp 445 "$VPC_CIDR" "SMB"
add_rule tcp 135 "$VPC_CIDR" "RPC"
add_rule tcp 49152-65535 "$VPC_CIDR" "Dynamic RPC"
add_rule udp 3343 "$VPC_CIDR" "Cluster Service UDP"
add_rule tcp 5985 "$VPC_CIDR" "WinRM HTTP"

echo ""
echo "===== Security Group Rules Added Successfully! ====="
echo ""
echo "You can now:"
echo "1. Test DNS from SQL nodes: nslookup contoso.local <DC_IP>"
echo "2. Join SQL nodes to domain: Run 03-Join-Domain.ps1"
echo ""

