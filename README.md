
#Three Tier Web Application 

AWS VPC, Application Load Balancer, Auto Scaling group and RDS Multi-AZ,
built entirely with Terraform.

##Decisions

  ** Three route tables, not two - Both public subnets share one, because they
  send internet traffic to the same internet gateway. Each private subnet gets
  its own, because each will route to the NAT gateway in its own zone — a
  shared one would send a live zone's traffic through a dead one.

  **Private subnets are explicitely associated with their own route tables rather than inheriting the VPC's main route table, so they can't acquire an internet route that wasn't written intentionally. 

  ** One NAT Gateway per zone - adds cost but one Gateway would be a single point of failure. 

  ** S3 Gateway Endpoint - Free and avoides charges for NAT usage.

  ** NAT Gateway needed the "depends_on" argument since it is not referenced elsewhere. 

  ** Added vpc_endpoint_type - clarifies what the endpoint is when reading instead of having to know "default" value. 

  ** Security groups - Load balancer will listen on Port 80, not 443 - I do not have a domain for a TLS Certificate. 
                     - The DB does not get an outbound rule, since it does not need to initiate communication - Least Proivoledge. 
                     - Security groups reference eachother everywhere the other end is inside the design. Outbound from the application tier is the one exception because the destinations are public and can't be enumerated - this is acceptable because security groups are stateful and the application tier has no inbound path from the internet. 
