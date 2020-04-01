OCI CLI automated installation on multiple hosts
---

Installation of OCI for some reasons requires manual operation. This howto explains automated way using expect and ansible to install OCI CLI for all users and multiple machines.

# Preparation
Before installation you need to collect: 
1. tenancy OCID, user OCID, OCI region name
2. credentials to open OCI console

To install you need to ensure that:
1. all nodes need are manageable by ansible
2. all nodes have access to internet to access yum and github

# Installation

Installation is performed from Linux session with available Ansible. 

## set parameters
Set parameters of your OCI environment.

```
user_OCID=ocid1.user.oc1..TAKE_FROM_YOUR_SYSTEM
region=eu-frankfurt-1-TAKE_FROM_YOUR_SYSTEM
tenancy=ocid1.tenancy.oc1..TAKE_FROM_YOUR_SYSTEM
```

## collect software
OCI CLI installaton requires git, python3, curl. Git must be avalable now to get scripts, but the rest is automatically installed by ansible defined logic.

```
yum install -y git
mkdir -p ipsec_cluster
cd ipsec_cluster
if [ ! -d ipsec-partner ]; then
    git clone https://github.com/rstyczynski/ipsec-partner.git
else
    cd ipsec-partner
    git pull
    cd ..
fi
cd ipsec-partner/working
source install_oci_cli_functions.sh
```

## generate key
Key is generated for Libreswan OCI client. Note that the contents of oci_api_key_ipsec_public.pem must by copy/pasted to OCI console. 

```
generateKey oci_api_key_ipsec
```

## enter public key into User's API KEY
Open OCI console, go to your profile (right upper corner), click API Keys, and press Add API Key. Paste key displayed by generateKey function.

## build OCI config file 
Execute function building OCI config. Note that function uses provided parameters and output of generate key. Execute all in the same session. 

```
buildOCIconfig
```

## specify target hosts 
Specify list of target hosts to install OCI CLI. Use ansible format. If needed add ansible_user variable.

```
cat >deploy_oci_cli.inventory <<EOF
[oci_cli]
192.168.1.51
192.168.1.52 
EOF
```

## Deploy OCI CLI to nodes
Once all preparation steps are completed. You may deploy OCI CLI to list of nodes specified in the inventory file. After deployment you should see OCI connectivity report for each node. I case of issues verify all parameters; add -vvv to below command line to see detailed debug information.

```
ansible-playbook install_oci_cli.yaml -i deploy_oci_cli.inventory
```

All done.

