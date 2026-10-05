
#Three Tier Web Application 

AWS VPC, Application Load Balancer, Auto Scaling group and RDS Multi-AZ,
built entirely with Terraform.

##Decisions

- **Three route tables, not two.** Both public subnets share one, because they
  send internet traffic to the same internet gateway. Each private subnet gets
  its own, because each will route to the NAT gateway in its own zone — a
  shared one would send a live zone's traffic through a dead one.

  **Private subnets are explicitely associated with their own route tables rather than inheriting the VPC's main route table, so they can't acquire an internet route that wasn't written intentionally. 