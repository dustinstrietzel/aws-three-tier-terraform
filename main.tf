#Data Blocks
data "aws_availability_zones" "available" {}


#Network resources
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.projecttf.id

  tags = {
    Name = "Terraform_Project"
  }
}

resource "aws_vpc" "projecttf" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Terraform_Project"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public-a"
  }
}
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "public-b"
  }
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-a"
  }
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-b"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.projecttf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }


  tags = {
    Name = "public-rt"
  }
}
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.projecttf.id

  tags = {
    Name = "private-a-rt"
  }
}
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.projecttf.id

  tags = {
    Name = "private-b-rt"
  }
}
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}