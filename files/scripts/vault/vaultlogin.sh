#!/bin/bash
# Vault EC2 secure introdution script
#
# Expects the following environment variables to be set:
#
# VAULT_ADDR - url of the Vault Service
# VAULT_ROLE - Vault role to attempt login with
# VAULT_PET  - A value of 1 indicates the nonce will be securely stored for
#              EC2s that need to survive a reboot
##############################################################################
readonly nonce_file=~/.hcvault/nonce
readonly temp_token_file=/tmp/ec2token

echo Vault secure introduction service starting
source /etc/environment
# Check service isn't already running / hasn't ran - this is fatal for the cubbyhole!

me=`basename "$0"`

for pid in $(pidof -x $me); do
    if [ $pid != $$ ]; then
      echo Instance duplicate - terminating
      exit 0
    fi
done


if [ -f /var/run/$me.pid ] ; then
  echo Service has already ran - terminating
  exit 0
fi

echo $$ >/var/run/$me.pid

# Check Vault is actually required
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_ROLE" ] ; then 
  echo No Vault parameters supplied - terminating
  exit 0
fi

# Default value for VAULT_PET
VAULT_PET=${VAULT_PET:-0}

echo VAULT_ADDR: $VAULT_ADDR
echo VAULT_ROLE: $VAULT_ROLE
echo VAULT_PET : $VAULT_PET
echo nonce_file: $nonce_file

# General exception handler
flunk()
{
	echo "${me} error: ${1:-"Unknown Error"}" 1>&2
	exit 1
}

# Json parser
parsejson()
{
  local parsed=`echo $@ | sed 's/\\\\\//\//g' | \
  sed 's/[{}]//g' | \
  awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | \
  sed 's/\"\:\"/\|/g' | \
  sed 's/[\,]/ /g' | \
  sed 's/\"//g'` \
  || flunk "Cannot Parse JSON"
  echo "$parsed"
}

if [ $VAULT_PET = 1 ] && [ -s $nonce_file ] ; then
  VAULT_NONCE=$(< $nonce_file)
  echo Nonce retrieved from $nonce_file
fi

# Grab the PKCS#7
PKCS7=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/pkcs7) \
|| flunk "Cannot retrieve PKCS7"
PKCS7=$(echo $PKCS7 | tr -d '\n')
echo PKCS#7 retrieved

if [ -z $VAULT_NONCE ]; then
# Attempt login without nonce
  echo Logging in without nonce...
  VAULT_LOGIN_RESPONSE=$(curl -s \
  -X POST \
  "${VAULT_ADDR}/v1/auth/aws/login" \
  -d '{"role":"'"$VAULT_ROLE"'","pkcs7":"'"$PKCS7"'"}') \
  || flunk "Can't log into Vault"
  echo Login call successful
else
# Attempt login with nonce
  echo Logging in with nonce...
  VAULT_LOGIN_RESPONSE=$(curl -s \
  -X POST \
  "${VAULT_ADDR}/v1/auth/aws/login" \
  -d '{"role":"'"$VAULT_ROLE"'","pkcs7":"'"$PKCS7"'","nonce":"'"$VAULT_NONCE"'"}') \
  || flunk "Can't log into Vault"
  echo Login call successful
fi

VAULT_LOGIN_PARSED=`parsejson $VAULT_LOGIN_RESPONSE`

# Get the token
VAULT_TOKEN=`echo "$VAULT_LOGIN_PARSED" | grep "client_token" | cut -f3 -d '|'`
if [ -z "$VAULT_TOKEN" ]; then
  flunk "Vault token is null: $VAULT_LOGIN_PARSED"
fi
echo Login token successfully retrieved

# For pets, store the nonce
if [ $VAULT_PET = 1 ] && [ -z $VAULT_NONCE ]; then
  VAULT_NONCE=`echo "$VAULT_LOGIN_PARSED" | grep "nonce" | cut -f2 -d'|'`
  if [ -z $VAULT_NONCE ]; then
    flunk "Null nonce retrieved from Vault"
  fi
  echo Nonce retrieved and written to $nonce_file
  # NB: ~/.vault is reserved for the Vault config file
  mkdir -p "$(dirname $nonce_file)"
  echo $VAULT_NONCE > $nonce_file
fi

# Create a temporary token with no parent policies
VAULT_RESPONSE=$(curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    -X POST \
    -d '{ "ttl": "5m", "num_uses": "2", "policies": "default"}' \
    ${VAULT_ADDR}/v1/auth/token/create) \
    || flunk "Failure to create temporary token"
VAULT_CREATE_TOKEN_RESPONSE=`parsejson $VAULT_RESPONSE`
VAULT_TEMP_TOKEN=`echo "$VAULT_CREATE_TOKEN_RESPONSE" | grep "client_token" | cut -f3 -d '|'`
echo Temporary token created

# Cubbyhole the permenant token using the temporary token
curl -s \
    --header "X-Vault-Token: $VAULT_TEMP_TOKEN" \
    -X POST \
    -d '{ "client_token": "'"$VAULT_TOKEN"'"}' \
    ${VAULT_ADDR}/v1/cubbyhole/ec2token \
    || flunk "Failure to cubbyhole the temporary token"
echo Token sucessfully cubbyholed

# And write the temp token to disk
echo $VAULT_TEMP_TOKEN > $temp_token_file
chmod 755 $temp_token_file
echo Temporary token written to $temp_token_file
echo Vault secure introduction service ending