# Terraform AWS Network

A small Terraform project that creates the base AWS networking layer for an application.

The project intentionally keeps the file structure compact. Network resources remain together in `main.tf`, while Terraform/provider configuration, variables, and outputs are separated by responsibility.

## What this project creates

By default, Terraform creates:

- 1 custom VPC
- 2 public subnets
- 2 private subnets
- 1 Internet Gateway
- 1 Elastic IP
- 1 NAT Gateway
- 1 public route table
- 1 private route table
- Route table associations for every subnet

The public and private subnets are distributed across available AWS Availability Zones.

## Project structure

```text
terraform-common/
├── .github/
│   └── workflows/
│       ├── terraform.yaml
│       └── terraform-destroy.yaml
├── terraform.tf
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── .terraform.lock.hcl
├── .gitignore
└── README.md
```

Only four Terraform `.tf` files are used. This keeps the project easy to navigate without putting every resource type into a separate file.

---

## File explanation

### `terraform.tf`

Contains Terraform itself and AWS provider configuration.

It defines:

- Minimum supported Terraform version
- AWS provider source
- Allowed AWS provider version range
- S3 remote state backend
- AWS region
- Default tags applied to resources

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  backend "s3" {}
}
```

Keeping this configuration outside `main.tf` makes it immediately clear which Terraform and provider versions the project expects.

The `backend "s3" {}` block is intentionally empty (partial configuration). The bucket, key, and region are passed at `terraform init` time, so no account-specific values are committed. See [Remote state](#remote-state).

The provider also applies common tags:

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.project_name
        ManagedBy = "Terraform"
      },
      var.tags
    )
  }
}
```

This means you do not need to repeat `Project`, `ManagedBy`, and environment-specific tags on every AWS resource.

---

### `main.tf`

Contains the actual AWS network infrastructure.

#### Availability Zones

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

Terraform asks AWS which Availability Zones are available in the selected region.

The first subnet is placed in the first available AZ, the second subnet in the second AZ, and so on.

This avoids hardcoding values such as `eu-central-1a` and `eu-central-1b`.

#### VPC

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}
```

The VPC is the isolated network that contains all of the subnets and future application resources.

Default CIDR:

```text
10.0.0.0/16
```

DNS support and DNS hostnames are enabled because AWS services and EC2 instances commonly rely on internal DNS resolution.

#### Internet Gateway

The Internet Gateway is attached to the VPC and provides an Internet path for public subnets.

```text
Public subnet -> Public route table -> Internet Gateway -> Internet
```

An Internet Gateway alone does not make a subnet public. A subnet becomes public because its route table contains a default route to the Internet Gateway.

#### Public subnets

By default:

```text
10.0.1.0/24
10.0.2.0/24
```

Public subnets use:

```hcl
map_public_ip_on_launch = true
```

Therefore, EC2 instances launched directly into these subnets can automatically receive public IPv4 addresses when their network interface configuration allows it.

Each subnet is named `<project_name>-public-<n>` or `<project_name>-private-<n>` and gets a `Tier` tag (`public` or `private`), which makes it easy to look subnets up by tier later.

Typical resources placed in public subnets include:

- Internet-facing Application Load Balancers
- NAT Gateways
- Bastion hosts, if a bastion architecture is used

Application servers normally belong in private subnets instead.

#### Private subnets

By default:

```text
10.0.101.0/24
10.0.102.0/24
```

Private subnets do not automatically assign public IP addresses.

Typical resources placed here include:

- EC2 application instances
- Auto Scaling Group instances
- ECS services/tasks
- Internal services

RDS databases also normally live in private subnets, although a real RDS deployment should usually have a dedicated DB subnet group and appropriate security groups.

#### Elastic IP

The NAT Gateway needs a stable public IPv4 address.

Terraform therefore creates an Elastic IP and assigns it to the NAT Gateway.

#### NAT Gateway

The NAT Gateway is created in the first public subnet.

Its purpose is to allow resources in private subnets to initiate outbound Internet connections without making those resources publicly reachable.

For example:

```text
Private EC2
    |
Private route table
    |
NAT Gateway
    |
Internet Gateway
    |
Internet
```

This is useful when private EC2 instances need to:

- Download OS packages
- Pull Docker images
- Access external APIs
- Download application dependencies

The Internet cannot use the NAT Gateway to initiate a connection back to the private EC2 instance.

This project creates only one NAT Gateway to keep the infrastructure simpler and cheaper.

For a highly available production setup, you would normally create one NAT Gateway per Availability Zone and give each private subnet a route to the NAT Gateway in the same AZ.

#### Public route table

The public route table contains:

```text
Destination: 0.0.0.0/0
Target:      Internet Gateway
```

`0.0.0.0/0` means all IPv4 destinations not already matched by a more specific route.

All public subnets are associated with this route table.

#### Private route table

The private route table contains:

```text
Destination: 0.0.0.0/0
Target:      NAT Gateway
```

All private subnets are associated with this route table.

This is what gives private instances outbound Internet access while keeping them without direct public Internet exposure.

---

### `variables.tf`

Defines the configurable inputs for the network.

The current variables are:

| Variable | Default | Purpose |
| --- | --- | --- |
| `aws_region` | `eu-central-1` | AWS region where resources are created |
| `project_name` | `app` | Prefix used in names and tags |
| `vpc_cidr` | `10.0.0.0/16` | IP range of the complete VPC |
| `public_subnet_cidrs` | `10.0.1.0/24`, `10.0.2.0/24` | Public subnet ranges |
| `private_subnet_cidrs` | `10.0.101.0/24`, `10.0.102.0/24` | Private subnet ranges |
| `tags` | `{}` | Additional tags applied globally |

Variables allow the same Terraform code to be reused for dev, test, staging, or production environments without editing resource definitions.

---

### `outputs.tf`

Exposes important IDs after Terraform creates the network.

Outputs include:

- VPC ID
- Public subnet IDs
- Private subnet IDs
- Public route table ID
- Private route table ID
- Internet Gateway ID
- NAT Gateway ID
- Availability Zones used

For example, a future Auto Scaling Group configuration can use:

```hcl
vpc_zone_identifier = module.network.private_subnet_ids
```

A future public Application Load Balancer could use:

```hcl
subnets = module.network.public_subnet_ids
```

Outputs therefore make it easy to connect this network layer to the next Terraform resources you add.

---

### `terraform.tfvars.example`

Shows an example set of real values for the input variables.

Terraform automatically reads a file named:

```text
terraform.tfvars
```

The example file is intentionally committed instead of the real `terraform.tfvars` file.

Create your local file with:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then change the values for your environment.

Example:

```hcl
aws_region   = "eu-central-1"
project_name = "my-app"

tags = {
  Environment = "dev"
  Owner       = "platform-team"
}
```

Do not put AWS access keys or other secrets in this file.

---

### `.gitignore`

Prevents local Terraform files from being accidentally committed.

Most importantly, it excludes:

- `.terraform/`
- Terraform state files (`*.tfstate`, `*.tfstate.*`)
- `terraform.tfvars` and `*.auto.tfvars`
- Local plan files (`*.tfplan`)
- `.idea` IDE settings

Terraform state can contain infrastructure details and sometimes sensitive information, so state should never be committed to Git. This project keeps state in S3 instead (see [Remote state](#remote-state)).

---

## Network architecture

```text
                            Internet
                               |
                      +------------------+
                      | Internet Gateway |
                      +------------------+
                               |
                +-----------------------------+
                |      Public Route Table     |
                |       0.0.0.0/0 -> IGW      |
                +-----------------------------+
                    |                     |
                    |                     |
          +------------------+   +------------------+
          | Public Subnet 1  |   | Public Subnet 2  |
          |       AZ-1       |   |       AZ-2       |
          +------------------+   +------------------+
                    |
              +-------------+
              | NAT Gateway |
              +-------------+
                    |
                +--------------------------------+
                |      Private Route Table       |
                |      0.0.0.0/0 -> NAT GW       |
                +--------------------------------+
                    |                      |
          +-------------------+   +-------------------+
          | Private Subnet 1  |   | Private Subnet 2  |
          |       AZ-1        |   |       AZ-2        |
          +-------------------+   +-------------------+
```

## Public vs private traffic

### Public subnet resource

A public EC2 instance can have this path:

```text
EC2 -> Public Route Table -> Internet Gateway -> Internet
```

For inbound traffic to work, the instance must also have a public IP and its Security Group must allow the required inbound traffic.

### Private subnet resource

A private EC2 instance uses:

```text
EC2 -> Private Route Table -> NAT Gateway -> Internet Gateway -> Internet
```

The instance does not need a public IP.

Inbound Internet traffic cannot directly reach it through the NAT Gateway.

## Security Groups

This project intentionally does not create application Security Groups.

Security Groups are easier to manage when they are defined together with the resources they protect.

For example, a future application architecture might use:

```text
Internet
   |
ALB Security Group
   | allow application port
EC2 / ASG Security Group
   | allow DB port
RDS Security Group
```

That is better than creating generic Security Groups in the networking project before we know exactly which services and ports are required.

The VPC's default Network ACL remains in place. No custom NACL is created because Security Groups are sufficient for the initial architecture and adding unnecessary NACL rules would make the setup harder to maintain.

## Remote state

Terraform state is stored in an S3 bucket using the S3 backend. State locking uses an S3 lock file (`use_lockfile = true`), so no DynamoDB table is needed.

| Setting | Value |
| --- | --- |
| Bucket | Provided at init (`TF_STATE_BUCKET` secret in CI) |
| Key | `infrastructure/terraform.tfstate` |
| Region | Provided at init (`AWS_REGION` secret in CI) |
| Encryption | Enabled (`encrypt = true`) |
| Locking | S3 lock file (`use_lockfile = true`) |

The state bucket is **not** created by this project. It must exist before the first `terraform init`.

S3-native locking (`use_lockfile`) requires Terraform 1.10 or newer, even though `required_version` allows 1.6+.

For local runs, create a `backend.hcl` file (do not commit it) with the same values CI uses:

```hcl
bucket       = "<your-state-bucket>"
key          = "infrastructure/terraform.tfstate"
region       = "eu-central-1"
encrypt      = true
use_lockfile = true
```

Then initialize with:

```bash
terraform init -backend-config=backend.hcl
```

Running plain `terraform init` without backend configuration will prompt for the missing backend values.

## CI/CD

GitHub Actions workflows in `.github/workflows/` run Terraform against the shared S3 state. Authentication uses GitHub OIDC to assume an AWS IAM role, so no long-lived AWS keys are stored in GitHub.

### `terraform.yaml` — Terraform CI

Runs on pull requests to `main` and on pushes to `main`:

1. `terraform fmt -check -recursive`
2. `terraform init` with the S3 backend configuration
3. `terraform validate`
4. `terraform plan`
5. `terraform apply` of the saved plan: **only on push to `main`**, and only when all previous steps succeeded

On pull requests, a report with the check results and the plan is added to the PR description. The job fails if any check fails.

### `terraform-destroy.yaml` — Terraform Destroy

Triggered manually (`workflow_dispatch`). It only runs when the `confirmation` input is exactly `DESTROY`, and then destroys all resources tracked in the S3 state.

Both workflows share a concurrency group, so an apply and a destroy never run at the same time.

### Required GitHub configuration

| Name | Type | Purpose |
| --- | --- | --- |
| `AWS_PLAN_ROLE_ARN` | Secret | IAM role assumed through OIDC |
| `AWS_REGION` | Secret | AWS region for the provider and the state bucket |
| `TF_STATE_BUCKET` | Secret | Name of the S3 bucket holding Terraform state |
| `TF_VERSION` | Variable | Terraform version installed in the workflow (1.10+) |

## Prerequisites

You need:

- Terraform 1.10 or newer installed
- AWS CLI installed or another valid AWS authentication method
- AWS credentials configured
- Permission to create VPC/network resources
- An existing S3 bucket for Terraform state, and read/write access to it

Verify AWS authentication with:

```bash
aws sts get-caller-identity
```

## Running Terraform with a Specific AWS Profile

This project does not store AWS access keys directly in the Terraform files. Instead, it uses an AWS CLI profile configured on your local machine.

For example, if your AWS profile is named:

```bash
terraform-user
```

you can verify that the profile is configured correctly with:

```bash
aws sts get-caller-identity --profile terraform-user
```

If the command succeeds, run Terraform by passing the profile through the `AWS_PROFILE` environment variable.

Initialize Terraform:

```bash
AWS_PROFILE=terraform-user terraform init -backend-config=backend.hcl
```

Validate the configuration:

```bash
AWS_PROFILE=terraform-user terraform validate
```

Preview the infrastructure changes:

```bash
AWS_PROFILE=terraform-user terraform plan
```

Create or update the AWS infrastructure:

```bash
AWS_PROFILE=terraform-user terraform apply
```

Terraform will display the planned changes and ask for confirmation before creating resources.

To destroy the resources managed by this project:

```bash
AWS_PROFILE=terraform-user terraform destroy
```

Using `AWS_PROFILE` keeps AWS credentials outside the Terraform source code and makes it easy to switch between different AWS users or accounts.

For example:

```bash
AWS_PROFILE=terraform-user terraform plan
AWS_PROFILE=dev-user terraform plan
AWS_PROFILE=production-user terraform plan
```

The profile name refers to a profile stored in the local AWS configuration, typically under:

```text
~/.aws/credentials
~/.aws/config
```

Do not commit AWS access keys, secret keys, or credential files to the repository.


## Deploy

### 1. Create the local variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Initialize Terraform

```bash
terraform init -backend-config=backend.hcl
```

This downloads the AWS provider, connects to the S3 state backend, and prepares the Terraform working directory. See [Remote state](#remote-state) for the contents of `backend.hcl`.

### 3. Format the code

```bash
terraform fmt -recursive
```

### 4. Validate the configuration

```bash
terraform validate
```

### 5. Preview changes

```bash
terraform plan
```

Always review the plan before applying it.

### 6. Create the infrastructure

```bash
terraform apply
```

Terraform displays the plan again and asks for confirmation before creating the resources.

## Inspect outputs

After deployment:

```bash
terraform output
```

To retrieve only the VPC ID:

```bash
terraform output vpc_id
```

To retrieve private subnet IDs:

```bash
terraform output private_subnet_ids
```

## Destroy

To remove everything created by this project:

```bash
terraform destroy
```

Review the destroy plan before confirming it.

## NAT Gateway cost note

AWS NAT Gateways are billed while provisioned and also charge for processed data.

This project deliberately creates only one NAT Gateway because it is a good compromise for a development/training environment.

For production, availability requirements may justify one NAT Gateway in each Availability Zone even though that increases cost.

## What should come next

This network is ready to be used as the foundation for resources such as:

```text
Public subnets
├── Application Load Balancer
└── Bastion host (only if required)

Private subnets
├── EC2 Auto Scaling Group
├── Application servers
└── Containers

Private database layer
└── RDS + DB subnet group
```

A typical next Terraform step would be adding Security Groups and then deploying the application compute layer into the private subnets.
