resource "aws_vpc" "vpc"{
  cidr_block = "192.168.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc",
    "kubernetes.io/cluster/zop-groot" = "shared",
  }
}
//data "aws_availability_zone" "available" {}

resource "aws_subnet" "vpc-subnet" {
  count = 3
  // availability_zone = [ap-south-1a,ap-south-1b,ap-south-1c]
  cidr_block = "192.168.${count.index}.0/24"
  vpc_id = aws_vpc.vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "vpc-subnet",
    "kubernetes.io/cluster/zop-groot" = "shared",

  }
}

resource "aws_internet_gateway" "eks_dnat" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "eks-dnat"
  }
}

resource "aws_route_table" "eks-route-table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_dnat.id
  }
}

resource "aws_route_table_association" "eks-asoc" {
  count = 3

  subnet_id = aws_subnet.vpc-subnet.*.id[count.index]
  route_table_id = aws_route_table.eks-route-table.id
}





resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "zop-groot" {
  name     = "zop-groot"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.vpc-subnet[*].id
  }

  tags = {
    Name = "EKS_zop"
  }
}

resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group-tuto"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.zop-groot.name
  node_group_name = "node"
  instance_types = ["t2.micro"]
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.vpc-subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}