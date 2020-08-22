data "aws_availability_zones" "example" {
  state = "available"
}

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

resource "aws_eip_association" "eip_assoc" {
  instance_id   = module.ec2_cluster.id[0]
  allocation_id = aws_eip.nat[0].id
}