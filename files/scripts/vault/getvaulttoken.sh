#!/bin/bash
# Vault EC2 secure introdution script
#
# Expects the following environment variables to be set:
#
# VAULT_ADDR - url of the Vault Service
#############################################################################

# General exception handler
flunk()
{
  echo "${basename} error: ${1:-"Unknown Error"}" 1>&2
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

source /etc/environment

VAULT_TEMP_TOKEN=$(< /tmp/ec2token)

VAULT_RESPONSE=$(curl -s \
    --header "X-Vault-Token: $VAULT_TEMP_TOKEN" \
    "${VAULT_ADDR}/v1/cubbyhole/ec2token") \
    || flunk "Failure contacting Vault"
    
VAULT_GET_TOKEN_RESPONSE=`parsejson $VAULT_RESPONSE`

VAULT_TOKEN=`echo "$VAULT_GET_TOKEN_RESPONSE" | grep "client_token" | cut -f3 -d '|'`

if [ -z $VAULT_TOKEN ]; then
  flunk "Failure retrieving token from cubbyhole"
fi

echo $VAULT_TOKEN