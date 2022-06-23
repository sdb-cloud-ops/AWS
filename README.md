# Deploy infrastructure required to setup Kubernetes cluster on AWS with Terraform 

This purpose of this article is to automate the process of deploying infrastructure required to setup a Kubernetes cluster with Terraform.

We chose to use Kubespray to deploy our Kubernetes cluster. Kubespray is a composition of [Ansible](https://docs.ansible.com/) playbooks, [inventory](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ansible.md), provisioning tools, and domain knowledge for generic OS/Kubernetes clusters configuration management tasks. Kubespray provides:

* a highly available cluster
* composable attributes
* support for most popular Linux distributions
  * Ubuntu 16.04, 18.04, 20.04
  * CentOS/RHEL/Oracle Linux 7, 8
  * Debian Buster, Jessie, Stretch, Wheezy
  * Fedora 31, 32
  * Fedora CoreOS
  * openSUSE Leap 15
  * Flatcar Container Linux by Kinvolk
* continuous integration tests

To choose a tool which best fits your use case, read [this comparison](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/comparisons.md) to
[kubeadm](/docs/reference/setup-tools/kubeadm/) and [kops](/docs/setup/production-environment/tools/kops/).

## Installing Kubernetes with Kubespray on AWS

In this guide we will show how to deploy Kubernetes with Kubespray on AWS.

### Installing dependencies

Before deploying, we will need a virtual machine (hereinafter Jumpbox) with all the software dependencies installed. Check the list of distributions supported by Kubespray and deploy the Jumpbox with one of these distributions. Make sure to have the latest version of Python installed. Next, the dependencies from requirements.text in Kubespray’s GitHub repo must be installed.

```console
sudo pip install -r requirements.txt
```

Lastly, install Terraform by HashiCorp. Simply download the latest version of Terraform according to your distribution and install it to your /usr/local/bin folder. For example:

```console
wget https://releases.hashicorp.com/terraform/0.12.23/terraform_0.12.23_linux_amd64.zip

unzip terraform_0.12.23_linux_amd64.zip

sudo mv terraform /usr/local/bin/
```

### Building a cloud infrastructure with Terraform

Since Kubespray does not automatically create virtual machines, we need to use Terraform to help provision our infrastructure. 

To start, we create an SSH key pair for Ansible on AWS.

![Generate AWS Keypair](https://www.altoros.com/blog/wp-content/uploads/2020/03/Creating-SSH-key-pairs.png)

The next step is to clone the Kubespray repository into our jumpbox. 

```console
git clone https://github.com/sdb-cloud-ops/ss-k8s-kubespray.git
```

The Terraform scripts have been modified not to expose sensitive data such as credentials. We are instead using AWS profiles.

We then enter the cloned directory and copy the credentials.

```console
cd ss-k8s-kubespray/contrib/terraform/aws/
cp credentials.tfvars.example credentials.tfvars
```

After copying, fill out credentials.tfvars with our AWS credentials.

```console
vim credentials.tfvars
```

In this case, the AWS credentials were as follows.

```markdown
> **Note:** We are only specifying the region and key name in this example.
```

```console
# #AWS Access Key
# AWS_ACCESS_KEY_ID = ""
# #AWS Secret Key
# AWS_SECRET_ACCESS_KEY = ""
#EC2 SSH Key Name
AWS_SSH_KEY_NAME = "kube-ansible"
#AWS Region
AWS_DEFAULT_REGION = "us-east-1"
```

Below is an example AWS Profile. If you would like to learn more about working with multiple named AWS profiles, check [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html).

```console
cd ~/.aws
cat config
```
```markdown
[default]
region = us-east-1
output = json

[admin]
region = us-east-1
output = json
```

```console
cd ~/.aws
cat credentials
```

```markdown
[default]
aws_access_key_id = accesskeyidfordefaultprofile
aws_secret_access_key = secretkeyfordefaultprofile
aws_session_token =  tokenfordefaultprofileifexists

[admin]
aws_access_key_id = accesskeyidforadminprofile
aws_secret_access_key = secretkeyforadminprofile
aws_session_token = tokenforadminprofileifexists
```
Once AWS profile is setup we need to set the profile that we want to Terraform to work with.

```console
export AWS_PROFILE=admin
echo $AWS_PROFILE
```
````markdown
admin
````
Now to check if the config is working and the correct profile is selected you could use the aws cli command to list S3 buckets.

```console
aws s3 ls
```

If the output is as expected, your selected AWS profile is ready for use with Terraform. Below is an example Terraform custom config to deploy infrastructure across two availability zones.

#### provider.tf

```terraform
provider "aws" {
  profile                  = "admin"
  region                   = "us-east-1"
}
```

#### terraform.tfvars

```terraform
#Global Vars
aws_cluster_name = "ss-dev"

#VPC Vars
aws_vpc_cidr_block       = "10.250.192.0/18"
aws_cidr_subnets_private = ["10.250.192.0/20", "10.250.208.0/20"]
aws_cidr_subnets_public  = ["10.250.224.0/20", "10.250.240.0/20"]

# single AZ deployment
#aws_cidr_subnets_private = ["10.250.192.0/20"]
#aws_cidr_subnets_public  = ["10.250.224.0/20"]

# 3+ AZ deployment
#aws_cidr_subnets_private = ["10.250.192.0/24","10.250.193.0/24","10.250.194.0/24","10.250.195.0/24"]
#aws_cidr_subnets_public  = ["10.250.224.0/24","10.250.225.0/24","10.250.226.0/24","10.250.227.0/24"]

#Bastion Host
aws_bastion_num  = 1
aws_bastion_size = "t3.small"

#Kubernetes Cluster
aws_kube_master_num       = 3
aws_kube_master_size      = "t3.medium"
aws_kube_master_disk_size = 50

aws_etcd_num       = 3
aws_etcd_size      = "t3.medium"
aws_etcd_disk_size = 50

aws_kube_worker_num       = 3
aws_kube_worker_size      = "t3.medium"
aws_kube_worker_disk_size = 50

#Settings AWS ELB
aws_nlb_api_port    = 6443
k8s_secure_api_port = 6443
kube_insecure_apiserver_address = "0.0.0.0"

default_tags = {
  Owner   = "username"
  Project = "Project Description"
  "Cost Center" = "Dev team"
}

inventory_file = "../../../inventory/hosts"
```
#### variables.tf

```terraform
variable "AWS_SSH_KEY_NAME" {
  description = "Name of the SSH keypair to use in AWS."
}

variable "AWS_DEFAULT_REGION" {
  description = "AWS Region"
}

//General Cluster Settings

variable "aws_cluster_name" {
  description = "Name of AWS Cluster"
}

data "aws_ami" "distro" {
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-10-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["136693071363"] # Debian-10
}

//AWS VPC Variables

variable "aws_vpc_cidr_block" {
  description = "CIDR Block for VPC"
}

variable "aws_cidr_subnets_private" {
  description = "CIDR Blocks for private subnets in Availability Zones"
  type        = list(string)
}

variable "aws_cidr_subnets_public" {
  description = "CIDR Blocks for public subnets in Availability Zones"
  type        = list(string)
}

//AWS EC2 Settings

variable "aws_bastion_size" {
  description = "EC2 Instance Size of Bastion Host"
}

/*
* AWS EC2 Settings
* The number should be divisable by the number of used
* AWS Availability Zones without an remainder.
*/
variable "aws_bastion_num" {
  description = "Number of Bastion Nodes"
}

variable "aws_kube_master_num" {
  description = "Number of Kubernetes Master Nodes"
}

variable "aws_kube_master_disk_size" {
  description = "Disk size for Kubernetes Master Nodes (in GiB)"
}

variable "aws_kube_master_size" {
  description = "Instance size of Kube Master Nodes"
}

variable "aws_etcd_num" {
  description = "Number of etcd Nodes"
}

variable "aws_etcd_disk_size" {
  description = "Disk size for etcd Nodes (in GiB)"
}

variable "aws_etcd_size" {
  description = "Instance size of etcd Nodes"
}

variable "aws_kube_worker_num" {
  description = "Number of Kubernetes Worker Nodes"
}

variable "aws_kube_worker_disk_size" {
  description = "Disk size for Kubernetes Worker Nodes (in GiB)"
}

variable "aws_kube_worker_size" {
  description = "Instance size of Kubernetes Worker Nodes"
}

/*
* AWS NLB Settings
*
*/
variable "aws_nlb_api_port" {
  description = "Port for AWS NLB"
}

variable "k8s_secure_api_port" {
  description = "Secure Port of K8S API Server"
}

variable "kube_insecure_apiserver_address" {
  description = "tcp Port of K8S API Server"
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
}

variable "inventory_file" {
  description = "Where to store the generated inventory file"
}
```
#### backend.tf (To store remote state)

```terraform
terraform {
  backend "s3" {
    bucket = "backend-config-8375"
    key    = "dev/kubespray"
    region = "us-east-1"
  }
}
```
Next, initialize Terraform and run terraform plan to see any changes required for the infrastructure.

```console
terraform init
terraform plan -out kube-plan -var-file=credentials.tfvars
```
After, apply the plan that was just created. This begins deploying the infrastructure and may take a few minutes.

```console
terraform apply “kube-plan”
```

Once deployed, we can verify the infrastructure in our AWS dashboard.

<img width="1261" alt="image" src="https://user-images.githubusercontent.com/62608538/171557147-60bbd963-2671-44d3-a0d4-c08c2f78cc3c.png">

### Deploying a cluster with Kubespray

With the infrastructure provisioned, we can begin to deploy a Kubernetes cluster using Ansible. Start off by entering the Kubespray directory and use the Ansible inventory file created by Terraform.

```console
cd ~/ss-k8s-kubespray
cat inventory/hosts
```

Next, load the SSH keys, which were created in AWS earlier on. First, create a file (in our case, it will be located at ``~/.ssh/kube-ansible.pem``) and paste the private part of the key created at AWS there.

```console
cat “” > ~/.ssh/kube-ansible.pem
eval $(ssh-agent)
ssh-add -D
ssh-add ~/.ssh/kube-ansible.pem
```

Once the SSH keys are loaded, we can now deploy a cluster using Ansible playbooks. This takes roughly 20 minutes.

```console
ansible-playbook -i ./inventory/hosts ./cluster.yml -e ansible_user=admin -b --become-user=root --flush-cache
```

Configuring access to the cluster
Now that the cluster has been deployed, we can configure who has access to it. First, find the IP address of the first master.

```console
cat inventory/hosts
```

```yaml
[all]
ip-10-250-199-147.ec2.internal ansible_host=10.250.199.147
ip-10-250-199-223.ec2.internal ansible_host=10.250.199.223
ip-10-250-198-85.ec2.internal ansible_host=10.250.198.85
bastion ansible_host=44.203.184.144

[bastion]
bastion ansible_host=44.203.184.144

[kube_control_plane]
ip-10-250-199-147.ec2.internal

[kube_node]
ip-10-250-199-223.ec2.internal

[etcd]
ip-10-250-198-85.ec2.internal

[calico_rr]

[k8s_cluster:children]
kube_node
kube_control_plane
calico_rr

[k8s_cluster:vars]
apiserver_loadbalancer_domain_name="kubernetes-nlb-ss-dev-3bdcbf0d070c1428.elb.us-east-1.amazonaws.com"
```


After identifying the IP address, we can SSH to the first master.

```console
ssh  -F ssh-bastion.conf core@10.250.199.147
```

Once connected, we are set as a core user. Switch to the root user and copy the kubectl config located in the root home folder.

```console
sudo su -
cd ~/.kube
cat config
```
Highlight and copy the kubectl config as shown in the following image.

<img width="1512" alt="image" src="https://user-images.githubusercontent.com/62608538/175276867-36944217-18a4-4fe5-8e79-16a250362640.png">

Return to the jumpbox and go to ``kube/config``.

```console
exit
vim ~/.kube/config
```

In production, we would frequently have multiple environments with multiple Kubernetes clusters, hence we would be using merged Kubeconfig file and use contexts to switch between multiple clusters like below.

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJeU1EWXhOekV3TVRJeU0xb1hEVE15TURZeE5ERXdNVEl5TTFvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTk5yCkZLeHNwNU41SWNPQ2tpTTlCK1ZaSk8zZDB4SUI3TWhRenJzay90enNyd2VYSXhpZ0lWN0QyOVFzTjRGeEZCQm4KUzUwNG5HWWhiVmdyNWlzMG0wY1FRMGZNVTMwSVhMMkQrRVZIVXh1ejJTS09OWjBBbkJUMCtRaW9udEJCYWZpawpWSnZ6bytmZGhTMWFFMy9YdFBremZYYjkyK09LVzZKdUVMNW5qMFZsMnRtRnYwWmlZeW00TGZSZmZKdzVLdzNVCkxmQTRLQ2NCS3ZJa29Xd0hEakZnSnAyMkowanpraVJGZlJtMndBNjEvOVhYbWdUbnp6UjNxcG8xYjZkMHdCWkIKb056NUJuT2tLd3BlNUxiK3E1NkMvMTZ4RWFsakswb3dkTVRQM1F1QkVWWUZZYUVNd3JWT3ZVWVgzS2tXZjBlZApPc2sva0JiNE1vSUVrV1NYdTRrQ0F3RUFBYU5aTUZjd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZDUVZwRXZmdFdoeTR5QS9VZjEySGFBNHRDN2lNQlVHQTFVZEVRUU8KTUF5Q0NtdDFZbVZ5Ym1WMFpYTXdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBSkRuZmtuWkdKYVlJa04wUzRRaAp3eDI0ek16K3ZUcWtDZTJGQlNmUW5sM2xiYmVLOUpENGt6UTFJZEhoczY5SVR0VkF2SjhWNG1vSHVhang5OHh3CkludVhXdUMxMUpiRHZ3ajk3emx3QmVaOUkra2hBZ3JHb1FvMjJtNnp0czhQRVYyTUZZRFBERFA4NUZ2emVHL3EKQ0c1eVZjL3VpdGg0bTZlT1N4Y0RLWkdUU3ZCWkNuOW1iUGJ2aUNudnM1RkZESWtHZHZVYlY3Ykd4aC9jM3gxUgpkRS8yUjIyUmtLM2p5MUJYeW1zQmxwdVJPcEZ2YkdHdzJ3VTc3WnVHdzJVampGQStWVkV4dlFDMGZBb3ZzMVlhCkl6Ui9CQ1FYOUE0aWZVenN3M1F0V0k1UEl5S3cvSVRWVDJXSEhMblV2OEpDeTRTSjloR1psOFVvR1hnQ0NVdkEKRUZNPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    server: https://kubernetes.docker.internal:6443
  name: docker-desktop

- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJeU1EWXlNekE1TURneE1Wb1hEVE15TURZeU1EQTVNRGd4TVZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTTZrCnNHd1g3Q2dFLzVuaUdQbkw2ZDIwWVlITm00K0R3bVB5ak9KMlUvTUJUUmZZUGRHN214UFlXQndCTzgvQkhVYUcKRzFRL0o0aUpZSXdieE1HTEJOeVNEYVQ0dk5CVXZTeXVyRE81d0NYa1B3M0gxckJDOWsvdTF4NW5LSnVPRVc3cQoyV1BabW0xZ01ST1p2Ni9pNHdsMjhLbkZmUXYrZGVQMWh1ODh5ZndoU3o2OEdiK3A3aWFBa3hiVUpxWHQ4b1B5CnloUnZ6YTVYK1V1STMxNnRKbm1uejNBaW9QZ2lObWcvb2Z2YWNlYmR6cXZkNEhHcVB6Y1JDT0xGMmxVZEluTlYKQ0JYcjM0WWQrMFJOZUEyUEgrR2VMQkJKZXR3YmorMWxGVTNxb1YrSno5MzhJaVgrUVlFTllFaHVpeDNVaUlsdAp6T2VjdExocXFyMTM4TlpVSTQwQ0F3RUFBYU5aTUZjd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZPbDVoT0wwcUg4TTBMcUdvN21IeFg2QTNtNC9NQlVHQTFVZEVRUU8KTUF5Q0NtdDFZbVZ5Ym1WMFpYTXdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBQVZpMXN6bDd4L1p2NDhjcXREeQpEN01JcXAzM2ppSlR1N1A0Y01ocEVnSGFzT21ybHJWaXNocVdGb0g5YkMwRW1SVlpWVTR2NkJOSitBOFpkYzZ6CnI3a3BkR040Q1ViQ0tSU0xTVnVPREF1dXhYV3NzQmJiZUhNSEdiQVUvc00rNWdIdjNrUW9WVDUxVElYS0lUY1kKY2lnV2JOZ0o2MFJJN0I3OUVyVFpqTDRJc013YUJxVS9EU1E4TS9lY21kSS9sTllXdVJoUVFyaVhodlRiQWcrTgpoTDV5bG45TVRKSzhTUVZsaE5zQVdSV0RtU2plL0U1bk41WXhQbVpBMi9Od3ZvbkpjNkJjeWJ1bU1mc0pFSTNEClpacmJiNEN6aGFHWXJxdVVhWXhzVGRQb2ZkNTRIZDF0NUJzK2Z4MTI0U0FxMkJUK3pXTmNQOW01Kzk1MWNMODgKL1EwPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    server: https://kubernetes-nlb-ss-dev-3bdcbf0d070c1428.elb.us-east-1.amazonaws.com:6443
  name: ss-kubespray

contexts:
- context:
    cluster: docker-desktop
    user: docker-desktop
  name: docker-desktop

- context:
    cluster: ss-kubespray
    user: ss-kubespray
  name: ss-kubespray

users:
- name: docker-desktop
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURRakNDQWlxZ0F3SUJBZ0lJYjBQMjFxTU0vRVF3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TWpBMk1UY3hNREV5TWpOYUZ3MHlNekEyTVRjeE1ERXlNalJhTURZeApGekFWQmdOVkJBb1REbk41YzNSbGJUcHRZWE4wWlhKek1Sc3dHUVlEVlFRREV4SmtiMk5yWlhJdFptOXlMV1JsCmMydDBiM0F3Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLQW9JQkFRRE9SbFZKc09zQWUxZCsKSzhBYit2MUN2VFB4bGlVbHBNcWhDRSt3U3Z3eTYwZ0hZSFY5aGpsN0ZGV2xyWEl6QUcxTkQ4OVNkWTFGUkQ2VApVVE1qQSsxUW9aclYwWXVnR1VmNkhrUTJzNUtrTHZtQnJzK2R0RThoanNjVHZETjJFR1lZdmI3cW9qRTM4ODlMCitnYjhuMUgzUVQzUkRxOHFCdW9Wd0FSbDBRelBYMEhCMTFlWm96YURxRHZDV3ZPdlZicE0rRlNWNEJQWm5IWGQKbklwck5QQTArZTVsVjBZTWpEYkdIVGxPa1hLVVFiZmlmaVA2NlJ1ZmJXQ3hmbnFtemR4UkIrSlJtUkVhTFNVMAp1aEdTVTJBWlR3eml2UUt1dHpHSWNHanRhaXRlbkM3RllCNnZEdjQ5QUVNc3BsamZqR3NNUlF6dUFvUVIyTlFlCjhuM3Yrdk5EQWdNQkFBR2pkVEJ6TUE0R0ExVWREd0VCL3dRRUF3SUZvREFUQmdOVkhTVUVEREFLQmdnckJnRUYKQlFjREFqQU1CZ05WSFJNQkFmOEVBakFBTUI4R0ExVWRJd1FZTUJhQUZDUVZwRXZmdFdoeTR5QS9VZjEySGFBNAp0QzdpTUIwR0ExVWRFUVFXTUJTQ0VtUnZZMnRsY2kxbWIzSXRaR1Z6YTNSdmNEQU5CZ2txaGtpRzl3MEJBUXNGCkFBT0NBUUVBWmV2Skg5V0tWYmpMQVNQRXd5UUhEM1dBSG9sUFRwaTJzY2o3RnFDcEZ5Y29Mc1FmTDNldDdUSFEKeS9WeTdGQ25lWjVOc3gwQzBIc2xISVd1cFpJQWpJWDhLV3FxWkVPMUVSVWpqdEtQbEgwdng4SVVSRDF2SWtBbQphUm5uVE1lWDZXUERuODNDUExwbTh3T1RhbUdBWEV6L3VmYXNmYzZ3YWlZSTVDdEs4dFlBRVBJQ1E2bzJSeEk1Cm1ZRUZPU3hNTWRCb1lXWHJUMllpaXV1RXNGY2swUFVTeFdrRGpKYndsS2pMNmovdHh4UHZUVWJwa2xIZlZleUEKdVVtL2kxL1R6clQ2LzRBV3g1b2xzV01pODFZQkJBUnlBQXBQMVBTUFJIenQ2T1JIRlNwdGRuNUh2aFZqZUdISwpybWJMQ0xPb1ZuWDJTSCtpd0YzSXVOTmtkc05iclE9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVBemtaVlNiRHJBSHRYZml2QUcvcjlRcjB6OFpZbEphVEtvUWhQc0VyOE11dElCMkIxCmZZWTVleFJWcGExeU13QnRUUS9QVW5XTlJVUStrMUV6SXdQdFVLR2ExZEdMb0JsSCtoNUVOck9TcEM3NWdhN1AKbmJSUElZN0hFN3d6ZGhCbUdMMis2cUl4Ti9QUFMvb0cvSjlSOTBFOTBRNnZLZ2JxRmNBRVpkRU16MTlCd2RkWAptYU0yZzZnN3dscnpyMVc2VFBoVWxlQVQyWngxM1p5S2F6VHdOUG51WlZkR0RJdzJ4aDA1VHBGeWxFRzM0bjRqCit1a2JuMjFnc1g1NnBzM2NVUWZpVVprUkdpMGxOTG9Sa2xOZ0dVOE00cjBDcnJjeGlIQm83V29yWHB3dXhXQWUKcnc3K1BRQkRMS1pZMzR4ckRFVU03Z0tFRWRqVUh2Sjk3L3J6UXdJREFRQUJBb0lCQUNORk4zUWdRaTZVNklMMApiQ2JjcGMxeG1KNG9kRFdabGVRdkRhRXhVU3BMdk1jMklTRFRnS1NnOTN3YXlqb2FTcFl3cTl5SHFSNDg2dzQ1Cmhpcm9rdjJFaEhzbkYxN0tzOW42cnVORGxVRnBudFFqMWZBN1VvU0VhMW5laGxZYnU3bGpTRy9LUit3dlRqVEoKamNSSVliV0xmRXh3M0ZhdFUvMWdGZUJxL0d2QXFUcWhnamxwQWRubTBMRmp0UHNEYUxQK2hxNlE5TEhhQ3hDNQp4a0ozVzB3WFBEMGlIS0FRK1hlNkhSMXFqN0hWNVlxK2ZhREE5L2xGcksxcXN2RFMyakQvSm5palhQazQ5emRpCjlBZWdIV2tRSGI4aGRYaFdEZ092S1hjRlFGRTNDcUFQTGduRVZVZm1MZ0tldzdsbEZ3L2s0VDV2cFhBengzbEcKTy9UdFhnRUNnWUVBMStVd2UxeGF0WnZibTZtVmZUZ0RKYVJLZlczb0E3dkY4SEpxWlFGYVk0TFd6SHJCNkRGWQp1eW9sWkVRWGttMkxjMm01aDlyV1h3b050czh3UE0rRXh1MDNJNXdLK1NydTlDVjlTQ1ZCNm56ekR4cXpIcHNxClNtaWdmSXR3dFJVNXZ2d0NxOUZJbUw5YlBCdFZURjNhTC9kNGxtRDVFSFVGeWM1aHhhMFE4b0VDZ1lFQTlKZWsKc1grWXdIQnhPMi83NnFPS21sYUw0S0o0dmdvSmxOZ2xtc2o5R0xPNVpoTzk4ZGRyQWJGY1NPdkhxUExvdVNZZApTUWhrYWRWd1YyOUYzMFlpT1ZucWIwNGQrc1ZrZUR4M2E1RGl2YUwreEFCQldEbDcyajdtYkJUaEgrQm5hNlk3CjZQK2ZaaXU4TWNUemc1SVVpM2tMSDU1c3BhVjZSYnVyUE1mdXU4TUNnWUJmNktjREJtSWRyNkY5bzNhUGJDU3AKd2pSOVNDZjhFSnk4Vm5mQmF6cDJYcGVCdXo4TklXN2pwck41dVc0blZKYlFyTFVKRDBTUWIrenJ1MXNZaUsvWgpsMlFaWTZiVVRpaGRPWkpRVEl6ZDJLZzVtNGpiSGQ5SnN2VW9udUZ3OEg3NHd3ZUV3TEpaZVJqVXVPZkp4eCs0CmsxMTBvSnZFbmRmMmNNS3FpRm14QVFLQmdRQ2JkRW43ZWtKbWhOQ2kyMEM4VjZiL0F1U3lKL0VmcjVkNVg0cysKL21GR011d3h3WGhtM2VnbjBrYjZIY2p2U3p1NGVVNEJuZkRjQndqNHVVTXFiaFBRYWFLRGpaMm1SWkRlam1mRQpHUGpUV0dZZHdwL0ZaL3Vjc1grWDBBbHBUaUhOSElGVlRDcE9NSnZTOGY5bmJ3L1p1VnZsZzdZLzdaVngvcDROCjZuQ0VLd0tCZ0Q3K3lxSDdENzJINDF5dlVjOXlycGIzVnJoeGhxTjJ1VGEyNkE2czYxQ2VIZkZESURNcFFvUEsKK3BZbGpMNEZKZENIZDY0a25Bak4rcFJ6MVBpUlN2a0cvMW00aGNhSkwvTHhLSzYxK3owbElpRWhHWWg3UVNuTwprcDZqaEIwSHN1NmFHRk9VeHdXNGhGRzRkSjNVWHdTaHBZTDh0M29qb1NvWmxINitJZml6Ci0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==
- name: ss-kubespray
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURJVENDQWdtZ0F3SUJBZ0lJVWcrYURWVEJFZ1F3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TWpBMk1qTXdPVEE0TVRGYUZ3MHlNekEyTWpNd09UQTRNVE5hTURReApGekFWQmdOVkJBb1REbk41YzNSbGJUcHRZWE4wWlhKek1Sa3dGd1lEVlFRREV4QnJkV0psY201bGRHVnpMV0ZrCmJXbHVNSUlCSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQVE4QU1JSUJDZ0tDQVFFQXN5MkViL2R6NXoyWHYrNCsKU3l1TWFoZjY1U2EvdW9VdmYxUjZOejlSMzNwSUM3TG94bm8wYW1OOXJOWkpudlZRa2xtYStCYjZmL21Oa1BGagpWV0ZVQnJvZk1FZzRVdXFwdXJZNnZDQ1A5dGY4d3VoVmRwZjNEcUN1QzBMTTdvdnRQM1grUUJzMk0vVXdyZit6ClFTdDQxMVg1K2VWR21SbGlvQ3dUVmhubHJVdjcvd2VWQ3AyMkRtb1p5Z29tdUpleUlBT2x5QWxac1U2Zjl1R20KZXhxbDhEWTF6R3llNUw1R3I4dXFsVTBPdFBTb3N1NldibFY1azBSLzRUZEJmZlA3Ym9EWWN3Nnlia1oxTmtmVwpjQy9Rdm9XMXZhb2c3azdBc2c4Nk5MWTUxRUxxeXRiQ2o4NTVudE9OTUNIYjMvdzFFY1g0Vi9xSEJneHBQTk44CnIvRTdsd0lEQVFBQm8xWXdWREFPQmdOVkhROEJBZjhFQkFNQ0JhQXdFd1lEVlIwbEJBd3dDZ1lJS3dZQkJRVUgKQXdJd0RBWURWUjBUQVFIL0JBSXdBREFmQmdOVkhTTUVHREFXZ0JUcGVZVGk5S2gvRE5DNmhxTzVoOFYrZ041dQpQekFOQmdrcWhraUc5dzBCQVFzRkFBT0NBUUVBU2ludlU1RVRoZnpDeWM4R0VIQVNRUm03cmQ4cGRaMVF0Y1VoCnJXSERiMmlZOG90Z3NGUGg0bHNRV1BnbFBraGJwd0F0K3ozV1dOd2cwRlU3dUFUTjNmY200TTA3dUowV0k5aDYKOGxZUGxjNzdLQ3dCZzkvTUUrUkt0M2ZCd2k5R2ZNVUx2UTR6dW0rSXBQWXBpQTZKUis0cjRhOTQzUHFtNjV5MwpTMUhCUlpPNzB1WVlSYkxQLzFmYk1hQVgvSmZCVWx1V1o3Qi83b1FiT1VHZ3YvdXZ5eHJWbTUwa3R3d2JCTVRUCktRNG5ORnAxbERLVEc5ODFyaVNHUnozbmJzeUdibFJEVWpSR0FaS0lVWEhzdFl0bEdpeTU4dUYyd0ZCcE5kR1EKbVRxTUFaRHFXeHFWOUh2dElKUmgrWi9MbnRpOGsvWTFIRWhHZEt6dEp6enpQZWtTYnc9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFcEFJQkFBS0NBUUVBc3kyRWIvZHo1ejJYdis0K1N5dU1haGY2NVNhL3VvVXZmMVI2Tno5UjMzcElDN0xvCnhubzBhbU45ck5aSm52VlFrbG1hK0JiNmYvbU5rUEZqVldGVUJyb2ZNRWc0VXVxcHVyWTZ2Q0NQOXRmOHd1aFYKZHBmM0RxQ3VDMExNN292dFAzWCtRQnMyTS9Vd3JmK3pRU3Q0MTFYNStlVkdtUmxpb0N3VFZobmxyVXY3L3dlVgpDcDIyRG1vWnlnb211SmV5SUFPbHlBbFpzVTZmOXVHbWV4cWw4RFkxekd5ZTVMNUdyOHVxbFUwT3RQU29zdTZXCmJsVjVrMFIvNFRkQmZmUDdib0RZY3c2eWJrWjFOa2ZXY0MvUXZvVzF2YW9nN2s3QXNnODZOTFk1MUVMcXl0YkMKajg1NW50T05NQ0hiMy93MUVjWDRWL3FIQmd4cFBOTjhyL0U3bHdJREFRQUJBb0lCQVFDSHhIYTB6S0V6Vi9WegpobGdIWjRFbkp2S0N6bUM3T1k0ckFsejFIZkt3enB4bTJQTU82YXhyN09WZW9LVDZZTkhqZ3lnczBtU1BzZzIyCkJXS0tZSXhsNklRWGRySFBDbWIveG5Nczk5TitiRnpuWjFyUzJRVm9QUktFRCtMdTRuSXNBd0ZibkFMdlRkdk0KREpQTVR0OXE4NGZOOWhBUGxDK3FSSnVHUTJ0SWFxVXhaL2xIalhaZDlaMjhqMFc3UTdFckxSZmZkOXg3dGZ4cAo3TVozaVVBSkV2S1RWek91RmVrSTM2cXo0bVpVLzNkcjloaHY4bmxISTg3OVRBVTdrTHV5MUo1ZTNCVjBnOWl4CmUxTVlCWjd4QjcyeVFXRGp3c0pFYmYydUxWR0dFMFlFZEdPZjBjckEwTGora28wK1NGT1EyRnRRR2hpS3V6V2kKVm5FVmtxVUJBb0dCQU4rWVVyK1RMVld5UGxLUW9HT3ZrdTQ4Mm5YTVlWbExBSkRaVXJYWWY4cGVBdlVhd1lVTAphZnBTMEVBbkJvZ2RsNi9WQitkaXhROERNYTN3ZGIvVFRLMWd3a1QwWkcrbWYzZmozaDY3VUJzMVJCU3o5VVNWClRUdGl1Mk0waFpmVDE0aXRpd1BjMU9DK2x0T1d3TXpqQ2V4UHVEK0dEMEw4aVhaUFBQWnZHZjZCQW9HQkFNMGwKUVhGQ0JIUWVHbDJjRVQyNitrY0JHeGtmUmswZTh6QTg0VS91akFpZXowKzhPNENETHYxakpqSUh6azVzZTgyUApyek92Nm9yd2Jab01OUUZPS096QjZtT0lySTcxMFFQblEwMjFwTGxYcTZnWEZzR2wvVjdsMTJEWCtYNnFpUnVBCkg1SG85OHpiZjBZZlFDakdhRFdRZ2YyV1lwZ1QwcmZNL2RUbEtGNFhBb0dCQUszY3MvdGpaZzBNM0lrM0RJQjMKTmJrcWVIVEF4N0czTUdseGsyN3pPZXNSenhyb0F6S0EvWmM0YmRaMGdnKzFjdzIyaUw3VGZvZDk1Rk5zZHlNQwpHczEyUDVsK3I5cGhqUnljZzB0Q083ZnNZMVAxMnZISlpwU1c0VDd5eUM2Vyt6RzhRQ3h3dXRkSFcrQ0xpTC9JCml4N0ZubTlHdnZkSGgxd0hvVSsrZEdnQkFvR0FOdHFqYVJseC8ycWRPaktsR1pDSm83clQrQis0dUo1eUFKQUcKMzB5MS9RZ1ovd1FpRlBiKzlab3hlR2RGN3dwckFFaFBYTTdKTkdXZHFQZGlwUHExVHJsN1p5b0FtaWw0dmtaMApaSzhSWU0za2hJbkg5L2ZlakNXQk5kQUtVcWhmQ1E5MVlacWR5QlZaTHZMa1FRTHNrb1lWZkMxZUo3UUZRRWg4CkJ4VlBlZmtDZ1lBVEd6bmNrazdySTdyWWdvcTUxSlU2Z09CUjdsNDUvalNrZm5tdmdkM2MxamdqQWtNQ2R3L1cKS2VGRjh3WVNUeFdMSXFnV3JRTGVoZGNONnBJcTRhWXd6TnkxWFBidHVkTGJjbmV3NVI2VmJCRFlrRUw3dHhtYwpHclJIUGpwWlExQldwMW4zWmM3SFI5WXNTZXJUMTA1cUpFR09qeWpaWFI5WXJnVDN2cm9vc3c9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQo=

current-context: docker-desktop
kind: Config
preferences: {}
```

Once you have the merged Kubeconfig in place, you could choose between multiple Kubernetes clusters / contexts with Docker Desktop or Kubectx. For more information on managing multiple Kubernetes clusters with Kubectx/Kubens and working with merged Kubeconfig, refer to this [link](https://computingforgeeks.com/manage-multiple-kubernetes-clusters-with-kubectl-kubectx/).

Next, copy the URL of the load balancer from the inventory file. In our case, the URL is ``kubernetes-nlb-ss-dev-3bdcbf0d070c1428.elb.us-east-1.amazonaws.com``. Paste this URL into the server parameter in kubectl config. Do not overwrite the port.

### Running test deployments

After configuring access to the cluster, we can check on our cluster. 

```console
kubectl get nodes
kubectl cluster-info
```
Node and cluster details will be shown in the console.

<img width="1512" alt="image" src="https://user-images.githubusercontent.com/62608538/175300463-1b25c38a-d968-45fd-8a58-d3044ae96815.png">

With the cluster ready, we can run a test deployment.

```console
kubectl create deployment nginx --image=nginx
kubectl get pods
kubectl get deployments
```

Entering this commands should deploy NGINX and also return the status of the pods and deployments.

<img width="1512" alt="image" src="https://user-images.githubusercontent.com/62608538/175300786-ec7695e7-b537-49d5-9d21-aebd9831ca5e.png">

With this, we have successfully provisioned our cloud infrastructure with Terraform. We then deployed a Kubernetes cluster using Kubespray. We also configured access to the cluster and finally we ran the test deployments.

More on Kubespray can be found in its [GitHub repository](https://github.com/kubernetes-sigs/kubespray), as well as in the project’s [official documentation](https://kubespray.io/#/).
