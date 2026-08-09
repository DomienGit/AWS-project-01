#!/usr/bin/env bash
# recreate.sh — odbudowuje topologię: VPC1, VPC2, subnety, IGW, NAT GW, EIP, RT, TGW, SG.
# Zapisuje nowe ID-ki do ~/devops-vars.sh przez savevar().
#
# ZAŁOŻENIA (edytuj jeśli miałeś inaczej):
#   Region:    eu-central-1
#   AZ:        eu-central-1a (single-AZ)
#   VPC1:      192.168.0.0/16  (app)
#   VPC2:      172.32.0.0/16   (secondary, tylko dla demonstracji TGW)
#   Subnety:   .1.0/24 = public,  .10.0/24 = private
#
# Użycie:  ./recreate.sh
# Czas:    ~10-15 min (NAT GW + TGW attachments tworzą się długo)

set -euo pipefail  # -e: fail fast na pierwszym błędzie (teardown ma -uo pipefail bo musi tolerować "already deleted")

# === KONFIGURACJA (edytuj jeśli potrzeba) ===
# Region hardcoded — jeśli chcesz inny, zmień tutaj. Nie polegamy na AWS_DEFAULT_REGION
# (env var nadpisywał fallback i komendy szły w zły region).
REGION="eu-central-1"
AZ="eu-central-1a"  # single-AZ; dla multi-AZ rozbuduj na eu-central-1b + kolejne subnety

VPC1_CIDR="192.168.0.0/16"
VPC2_CIDR="172.32.0.0/16"
PUB1_CIDR="192.168.1.0/24"    # VPC1 public  (eu-central-1a)
PRIV1_CIDR="192.168.10.0/24"  # VPC1 private (eu-central-1a)
PUB2_CIDR="172.32.1.0/24"     # VPC2 public  (eu-central-1a)
PRIV2_CIDR="172.32.10.0/24"   # VPC2 private (eu-central-1a)

# === Definicja savevar jeśli nie istnieje w shellu ===
if ! type savevar >/dev/null 2>&1; then
  savevar() {
    local name="$1" value="$2"
    local file=~/devops-vars.sh
    touch "$file"
    if grep -q "^${name}=" "$file"; then
      sed -i "s|^${name}=.*|${name}=\"${value}\"|" "$file"
    else
      echo "${name}=\"${value}\"" >> "$file"
    fi
  }
fi

# Wczytaj istniejące vars (AMI, KEY_NAME itp.)
[[ -f ~/devops-vars.sh ]] && source ~/devops-vars.sh

echo "=== RECREATE ==="
echo "Region: $REGION | AZ: $AZ"
echo "VPC1: $VPC1_CIDR (app) | VPC2: $VPC2_CIDR (secondary)"
echo
read -r -p "Kontynuować? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Anulowano."; exit 0; }
echo

# === [1/10] VPCs ===
echo "--- [1/10] VPCs ---"
VPC1_ID=$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC1_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=app-vpc}]" \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC1_ID" --enable-dns-hostnames >/dev/null
savevar VPC1_ID "$VPC1_ID"
echo "VPC1: $VPC1_ID"

VPC2_ID=$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC2_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=secondary-vpc}]" \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC2_ID" --enable-dns-hostnames >/dev/null
savevar VPC2_ID "$VPC2_ID"
echo "VPC2: $VPC2_ID"

# === [2/10] Internet Gateways ===
echo "--- [2/10] Internet Gateways ---"
IGW1_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW1_ID" --vpc-id "$VPC1_ID"
savevar IGW1_ID "$IGW1_ID"
echo "IGW1: $IGW1_ID"

IGW2_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW2_ID" --vpc-id "$VPC2_ID"
savevar IGW2_ID "$IGW2_ID"
echo "IGW2: $IGW2_ID"

# === [3/10] Subnets ===
echo "--- [3/10] Subnets ---"
PUB1_ID=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC1_ID" --cidr-block "$PUB1_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=app-pub-1a}]" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUB1_ID" --map-public-ip-on-launch >/dev/null
savevar PUB1_ID "$PUB1_ID"
echo "PUB1: $PUB1_ID"

PRIV1_ID=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC1_ID" --cidr-block "$PRIV1_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=app-priv-1a}]" \
  --query 'Subnet.SubnetId' --output text)
savevar PRIV1_ID "$PRIV1_ID"
echo "PRIV1: $PRIV1_ID"

PUB2_ID=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC2_ID" --cidr-block "$PUB2_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-pub-1a}]" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUB2_ID" --map-public-ip-on-launch >/dev/null
savevar PUB2_ID "$PUB2_ID"
echo "PUB2: $PUB2_ID"

PRIV2_ID=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC2_ID" --cidr-block "$PRIV2_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-priv-1a}]" \
  --query 'Subnet.SubnetId' --output text)
savevar PRIV2_ID "$PRIV2_ID"
echo "PRIV2: $PRIV2_ID"

# === [4/10] Elastic IPs ===
echo "--- [4/10] Elastic IPs ---"
EIP1_ID=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
savevar EIP1_ID "$EIP1_ID"
EIP2_ID=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
savevar EIP2_ID "$EIP2_ID"
echo "EIP1: $EIP1_ID | EIP2: $EIP2_ID"

# === [5/10] NAT Gateways (każdy ~2-5 min) ===
echo "--- [5/10] NAT Gateways (każdy 2-5 min) ---"
NATGW1_ID=$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "$PUB1_ID" --allocation-id "$EIP1_ID" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=nat-vpc1}]" \
  --query 'NatGateway.NatGatewayId' --output text)
savevar NATGW1_ID "$NATGW1_ID"
NATGW2_ID=$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "$PUB2_ID" --allocation-id "$EIP2_ID" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=nat-vpc2}]" \
  --query 'NatGateway.NatGatewayId' --output text)
savevar NATGW2_ID "$NATGW2_ID"
echo "Czekam aż NAT GW available (NATGW1=$NATGW1_ID, NATGW2=$NATGW2_ID)..."
aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$NATGW1_ID" "$NATGW2_ID"

# === [6/10] Route Tables (publiczne przez IGW, prywatne przez NAT) ===
echo "--- [6/10] Route Tables ---"
# VPC1: publiczny RT
PUB_RT1_ID=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC1_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$PUB_RT1_ID" --gateway-id "$IGW1_ID" --destination-cidr-block 0.0.0.0/0 >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$PUB_RT1_ID" --subnet-id "$PUB1_ID" >/dev/null
savevar PUB_RT1_ID "$PUB_RT1_ID"
# VPC1: prywatny RT
PRIV_RT1_ID=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC1_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$PRIV_RT1_ID" --nat-gateway-id "$NATGW1_ID" --destination-cidr-block 0.0.0.0/0 >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$PRIV_RT1_ID" --subnet-id "$PRIV1_ID" >/dev/null
savevar PRIV_RT1_ID "$PRIV_RT1_ID"
# VPC2: publiczny RT
PUB_RT2_ID=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC2_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$PUB_RT2_ID" --gateway-id "$IGW2_ID" --destination-cidr-block 0.0.0.0/0 >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$PUB_RT2_ID" --subnet-id "$PUB2_ID" >/dev/null
savevar PUB_RT2_ID "$PUB_RT2_ID"
# VPC2: prywatny RT
PRIV_RT2_ID=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC2_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$PRIV_RT2_ID" --nat-gateway-id "$NATGW2_ID" --destination-cidr-block 0.0.0.0/0 >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$PRIV_RT2_ID" --subnet-id "$PRIV2_ID" >/dev/null
savevar PRIV_RT2_ID "$PRIV_RT2_ID"
echo "RT utworzone: PUB_RT1=$PUB_RT1_ID PRIV_RT1=$PRIV_RT1_ID PUB_RT2=$PUB_RT2_ID PRIV_RT2=$PRIV_RT2_ID"

# === [7/10] Transit Gateway ===
echo "--- [7/10] Transit Gateway ---"
TGW_ID=$(aws ec2 create-transit-gateway --region "$REGION" \
  --description "devops-tgw" \
  --options AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable \
  --tag-specifications "ResourceType=transit-gateway,Tags=[{Key=Name,Value=devops-tgw}]" \
  --query 'TransitGateway.TransitGatewayId' --output text)
savevar TGW_ID "$TGW_ID"
echo "TGW: $TGW_ID — czekam na available..."
aws ec2 wait transit-gateway-available --region "$REGION" --transit-gateway-ids "$TGW_ID"

# === [8/10] TGW attachments (VPC1, VPC2) ===
echo "--- [8/10] TGW attachments ---"
TGW_ATTACH1_ID=$(aws ec2 create-transit-gateway-vpc-attachment --region "$REGION" \
  --transit-gateway-id "$TGW_ID" --vpc-id "$VPC1_ID" --subnet-ids "$PUB1_ID" "$PRIV1_ID" \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
savevar TGW_ATTACH1_ID "$TGW_ATTACH1_ID"

TGW_ATTACH2_ID=$(aws ec2 create-transit-gateway-vpc-attachment --region "$REGION" \
  --transit-gateway-id "$TGW_ID" --vpc-id "$VPC2_ID" --subnet-ids "$PUB2_ID" "$PRIV2_ID" \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
savevar TGW_ATTACH2_ID "$TGW_ATTACH2_ID"
echo "Czekam na TGW attachments available..."
aws ec2 wait transit-gateway-attachment-available --region "$REGION" \
  --transit-gateway-attachment-ids "$TGW_ATTACH1_ID" "$TGW_ATTACH2_ID"

# === [9/10] Trasy TGW między VPC1 <-> VPC2 (we wszystkich RT) ===
echo "--- [9/10] TGW routes (VPC1<->VPC2) ---"
for rt in "$PUB_RT1_ID" "$PRIV_RT1_ID"; do
  aws ec2 create-route --region "$REGION" --route-table-id "$rt" \
    --destination-cidr-block "$VPC2_CIDR" --transit-gateway-id "$TGW_ID" >/dev/null
done
for rt in "$PUB_RT2_ID" "$PRIV_RT2_ID"; do
  aws ec2 create-route --region "$REGION" --route-table-id "$rt" \
    --destination-cidr-block "$VPC1_CIDR" --transit-gateway-id "$TGW_ID" >/dev/null
done
echo "TGW routes dodane"

# === [10/10] Security Groups (kaskadowe referencje) ===
echo "--- [10/10] Security Groups ---"
# Ręczne podanie IP laptopa — skrypt jest odpalany z CloudShell, więc curl checkip
# zwróciłby IP CloudShell (Frankfurt), a nie usera. SSH na Bastion musi działać z laptopa.
read -r -p "Podaj swój publiczny IP laptopa (np. 1.2.3.4): " MY_IP_INPUT
[[ -z "$MY_IP_INPUT" ]] && { echo "ERROR: IP wymagane dla BastionSG."; exit 1; }
MY_IP="${MY_IP_INPUT}/32"
savevar MY_IP "$MY_IP"

# BastionSG — SSH z mojego IP
BASTION_SG=$(aws ec2 create-security-group --region "$REGION" --group-name BastionSG \
  --description "Bastion SG" --vpc-id "$VPC1_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$BASTION_SG" \
  --protocol tcp --port 22 --cidr "$MY_IP" >/dev/null
savevar BASTION_SG "$BASTION_SG"
echo "BastionSG: $BASTION_SG (SSH from $MY_IP)"

# NginxSG — 80/443 z internetu, 22 z BastionSG
NGINX_SG=$(aws ec2 create-security-group --region "$REGION" --group-name NginxSG \
  --description "Nginx SG" --vpc-id "$VPC1_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$NGINX_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$NGINX_SG" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$NGINX_SG" \
  --protocol tcp --port 22 --source-group "$BASTION_SG" >/dev/null
savevar NGINX_SG "$NGINX_SG"
echo "NginxSG: $NGINX_SG"

# TomcatSG — 8080 z NginxSG, 22 z BastionSG
TOMCAT_SG=$(aws ec2 create-security-group --region "$REGION" --group-name TomcatSG \
  --description "Tomcat SG" --vpc-id "$VPC1_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$TOMCAT_SG" \
  --protocol tcp --port 8080 --source-group "$NGINX_SG" >/dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$TOMCAT_SG" \
  --protocol tcp --port 22 --source-group "$BASTION_SG" >/dev/null
savevar TOMCAT_SG "$TOMCAT_SG"
echo "TomcatSG: $TOMCAT_SG"

# DB_SG — 3306 z TomcatSG
DB_SG=$(aws ec2 create-security-group --region "$REGION" --group-name DB_SG \
  --description "Database SG" --vpc-id "$VPC1_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$DB_SG" \
  --protocol tcp --port 3306 --source-group "$TOMCAT_SG" >/dev/null
savevar DB_SG "$DB_SG"
echo "DB_SG: $DB_SG"

echo
echo "=== DONE ==="
echo "Wszystkie nowe ID-ki zapisane do ~/devops-vars.sh"
echo
echo "Kolejne kroki (ręcznie lub kolejne skrypty):"
echo "  1. Deploy bastionu (z $BASTION_SG, w $PUB1_ID)"
echo "  2. Maven build (z $MAVEN_AMI)"
echo "  3. 3-tier: RDS + Tomcat ASG + Nginx ASG + NLBs"
