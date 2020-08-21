provider "aws" {
  version = "~> 3.0"
  region  = var.region
  profile = "personal"
}

data "aws_availability_zones" "example" {
  state = "available"
}

# Create a VPC
resource "aws_eip" "nat" {
  count = 1
  vpc   = true
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs                 = data.aws_availability_zones.example.names
  public_subnets      = [cidrsubnet(var.vpc_cidr, 8, 0)]
  single_nat_gateway  = true
  reuse_nat_ips       = true
  external_nat_ip_ids = "${aws_eip.nat.*.id}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# resource "aws_vpc" "selected" {
#   cidr_block = "10.0.0.0/16"

#   tags = {
#     Env = "test"
#   }
# }

# resource "aws_subnet" "example" {
#   count             = 1
#   vpc_id            = aws_vpc.selected.id
#   availability_zone = data.aws_availability_zones.example.names[count.index]
#   cidr_block        = cidrsubnet(aws_vpc.selected.cidr_block, 8, count.index)

#   tags = {
#     Env  = "test"
#     Name = "test-subnet-${aws_vpc.selected.id}"
#   }
# }

module "test_ec2_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "user-service"
  description = "Security group for user-service with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

module "ec2_cluster" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"
  name    = "test cluster"

  instance_count = 1

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.id
  monitoring             = true
  vpc_security_group_ids = [module.test_ec2_sg.this_security_group_id]
  subnet_id              = module.vpc.public_subnets[0]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = module.ec2_cluster.id[0]
  allocation_id = aws_eip.nat[0].id
}
