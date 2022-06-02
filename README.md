# Deploy a Production Ready self hosted, highly available Kubernetes Cluster with Kubespray

This purpose of this article is to automate the process of setting up a Kubernetes cluster.

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
cd kubespray/contrib/terraform/aws/
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
cat config
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
