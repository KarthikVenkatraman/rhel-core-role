
# RHEL Core Role

An Ansible Role to provision the core RHEL capabilities.


## Configuration


* Localisation
* Prevent password expiry for ec2-user and root
* Setup the Aviva SSH banner
* Install core packages
* Set .aws/configuration for ec2-user and root
  * Region = eu-west-1
  * output = json
* Hardening to meet CIS RHEL 7 Profile 2
* Install and configure Splunk forwarder
* Install Vault EC2 secure introduction
