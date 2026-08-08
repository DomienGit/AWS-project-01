#!/usr/bin/env bash
# teardown.sh — usuwa VPC1, VPC2 i wszystkie zależne zasoby (NAT GW, TGW, EC2, SG, RT, subnety, IGW).
# ID VPC bierze z $VPC1_ID / $VPC2_ID w ~/devops-vars.sh (lub z argumentów komendy).
# Zachowuje: AMI (nginx/tomcat/maven), key pair, ~/devops-vars.sh.
# Bezpiecznie odpalać wielokrotnie (idempotentny) — skip'uje to co już usunięte.
#
# Użycie:
#   ./teardown.sh                   # bierze VPC1_ID/VPC2_ID z devops-vars.sh
#   ./teardown.sh vpc-aaa vpc-bbb   # podaj VPC ID bezpośrednio

set -uo pipefail
REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

# --- Wczytaj vars jeśli plik istnieje ---
[[ -f ~/devops-vars.sh ]] && source ~/devops-vars.sh

# --- Zbierz VPC IDs (z vars + argumentów) ---
declare -a VPCS=()
for v in VPC1_ID VPC2_ID APP_VPC_ID SECONDARY_VPC_ID; do
  id="${!v:-}"
  [[ -n "$id" ]] && VPCS+=("$id")
done
VPCS+=("$@")
# Deduplikacja + usunięcie pustych
mapfile -t VPCS < <(printf '%s\n' "${VPCS[@]}" | sort -u | grep -v '^$' || true)

if [[ ${#VPCS[@]} -eq 0 ]]; then
  echo "ERROR: brak VPC IDs. Ustaw VPC1_ID/VPC2_ID w ~/devops-vars.sh albo podaj jako argument."
  exit 1
fi

# SAFETY: odrzuć default VPC (AWS-managed, nigdy nie usuwać)
FILTERED=()
for vpc in "${VPCS[@]}"; do
  is_default=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$vpc" \
    --query 'Vpcs[0].IsDefault' --output text 2>/dev/null)
  if [[ "$is_default" == "true" ]]; then
    echo "ERROR: $vpc to default VPC (AWS-managed). Nie ruszam. Napraw VPC1_ID/VPC2_ID w devops-vars.sh."
    exit 1
  fi
  FILTERED+=("$vpc")
done
VPCS=("${FILTERED[@]}")

echo "=== TEARDOWN ==="
echo "Region: $REGION"
echo "VPCs: ${VPCS[*]}"
echo
read -r -p "Kontynuować? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Anulowano."; exit 0; }
echo

# === [1/10] EC2 instances — terminate ===
echo "--- [1/10] EC2 instances ---"
for vpc in "${VPCS[@]}"; do
  insts=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc" \
    --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
    --output text 2>/dev/null)
  if [[ -n "$insts" ]]; then
    echo "Terminating in $vpc: $insts"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $insts \
      --query 'TerminatingInstances[].{ID:InstanceId,State:CurrentState.Name}' --output table
    echo "Czekam na terminated..."
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids $insts
  else
    echo "Brak instancji w $vpc"
  fi
done

# === [2/10] NAT Gateways (async delete, trzeba czekać) ===
echo "--- [2/10] NAT Gateways ---"
NGWS_TO_WAIT=()
for vpc in "${VPCS[@]}"; do
  for ngw in $(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=vpc-id,Values=$vpc" \
    --query 'NatGateways[?State!=`deleted` && State!=`deleting`].NatGatewayId' \
    --output text 2>/dev/null); do
    echo "Deleting NAT GW: $ngw"
    aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$ngw"
    NGWS_TO_WAIT+=("$ngw")
  done
done
for ngw in "${NGWS_TO_WAIT[@]}"; do
  echo "Waiting for NAT GW $ngw (może trwać do 5 min)..."
  while true; do
    state=$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "$ngw" \
      --query 'NatGateways[0].State' --output text 2>/dev/null || echo "")
    [[ "$state" == "deleted" ]] && break
    echo "  state=$state, sleep 20s"
    sleep 20
  done
done

# === [3/10] Elastic IPs (niezsocjowane) ===
echo "--- [3/10] Elastic IPs ---"
for eip in $(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=domain,Values=vpc" \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text 2>/dev/null); do
  echo "Releasing EIP: $eip"
  aws ec2 release-address --region "$REGION" --allocation-id "$eip" 2>&1 | sed 's/^/    /' || true
done

# === [4/10] TGW attachments (do tych VPC) ===
echo "--- [4/10] TGW attachments ---"
ATTS_TO_WAIT=()
for vpc in "${VPCS[@]}"; do
  for att in $(aws ec2 describe-transit-gateway-attachments --region "$REGION" \
    --filters "Name=resource-id,Values=$vpc" "Name=resource-type,Values=vpc" \
    --query 'TransitGatewayAttachments[?State!=`deleted` && State!=`deleting`].TransitGatewayAttachmentId' \
    --output text 2>/dev/null); do
    echo "Deleting TGW attachment: $att"
    aws ec2 delete-transit-gateway-vpc-attachment --region "$REGION" \
      --transit-gateway-attachment-id "$att" 2>&1 | sed 's/^/    /' || true
    ATTS_TO_WAIT+=("$att")
  done
done
for att in "${ATTS_TO_WAIT[@]}"; do
  echo "Waiting for TGW attachment $att..."
  while true; do
    state=$(aws ec2 describe-transit-gateway-attachments --region "$REGION" \
      --transit-gateway-attachment-ids "$att" \
      --query 'TransitGatewayAttachments[0].State' --output text 2>/dev/null || echo "")
    [[ -z "$state" || "$state" == "deleted" ]] && break
    echo "  state=$state, sleep 15s"
    sleep 15
  done
done

# === [5/10] Transit Gateway (jeśli nie ma już attachmentów) ===
echo "--- [5/10] Transit Gateway ---"
if [[ -n "${TGW_ID:-}" ]]; then
  remaining=$(aws ec2 describe-transit-gateway-attachments --region "$REGION" \
    --filters "Name=transit-gateway-id,Values=$TGW_ID" \
    --query 'TransitGatewayAttachments[?State!=`deleted` && State!=`deleting`].TransitGatewayAttachmentId' \
    --output text 2>/dev/null)
  if [[ -z "$remaining" ]]; then
    echo "Deleting TGW: $TGW_ID"
    aws ec2 delete-transit-gateway --region "$REGION" --transit-gateway-id "$TGW_ID" 2>&1 | sed 's/^/    /' || true
    while true; do
      state=$(aws ec2 describe-transit-gateways --region "$REGION" --transit-gateway-ids "$TGW_ID" \
        --query 'TransitGateways[0].State' --output text 2>/dev/null || echo "")
      [[ -z "$state" || "$state" == "deleted" || "$state" == "deleting" ]] && break
      echo "  state=$state, sleep 15s"
      sleep 15
    done
  else
    echo "SKIP TGW $TGW_ID — ma jeszcze aktywne attachments: $remaining"
  fi
fi

# === [6/10] Custom Route Tables (zostaw main) ===
echo "--- [6/10] Custom Route Tables ---"
for vpc in "${VPCS[@]}"; do
  for rt in $(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc" \
    --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' \
    --output text 2>/dev/null); do
    # Disasocjuj najpierw
    for assoc in $(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$rt" \
      --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
      --output text 2>/dev/null); do
      echo "  disassociate $assoc"
      aws ec2 disassociate-route-table --region "$REGION" --association-id "$assoc" 2>&1 | sed 's/^/    /' || true
    done
    echo "Deleting RT: $rt"
    aws ec2 delete-route-table --region "$REGION" --route-table-id "$rt" 2>&1 | sed 's/^/    /' || true
  done
done

# === [7/10] Subnets ===
echo "--- [7/10] Subnets ---"
for vpc in "${VPCS[@]}"; do
  for sub in $(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].SubnetId' --output text 2>/dev/null); do
    echo "Deleting subnet: $sub"
    aws ec2 delete-subnet --region "$REGION" --subnet-id "$sub" 2>&1 | sed 's/^/    /' || true
  done
done

# === [8/10] Internet Gateways ===
echo "--- [8/10] Internet Gateways ---"
for vpc in "${VPCS[@]}"; do
  for igw in $(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$vpc" \
    --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null); do
    echo "Detach + delete IGW: $igw (from $vpc)"
    aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$igw" --vpc-id "$vpc" 2>&1 | sed 's/^/    /' || true
    aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$igw" 2>&1 | sed 's/^/    /' || true
  done
done

# === [9/10] Security Groups (zostaw default — usuwa się z VPC) ===
echo "--- [9/10] Security Groups ---"
for vpc in "${VPCS[@]}"; do
  for sg in $(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null); do
    echo "Deleting SG: $sg"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>&1 | sed 's/^/    /' || true
  done
done

# === [10/10] VPC ===
echo "--- [10/10] VPCs ---"
for vpc in "${VPCS[@]}"; do
  echo "Deleting VPC: $vpc"
  aws ec2 delete-vpc --region "$REGION" --vpc-id "$vpc" 2>&1 | sed 's/^/    /' || true
done

echo
echo "=== DONE ==="
echo "Pozostało na koncie: AMI (nginx/tomcat/maven), key pair, ~/devops-vars.sh (ze starymi ID-kami)"
echo "Aby odbudować topologię: ./recreate.sh"
