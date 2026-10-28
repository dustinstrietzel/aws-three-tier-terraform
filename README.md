# Three-Tier Web Application on AWS

A load-balanced web application in a custom VPC spanning two Availability Zones, built entirely in Terraform — no console steps at any point.

Three tiers: a public load balancer, application servers in an Auto Scaling group, and a database. **Each tier can only be reached by the tier directly above it.** The internet reaches only the load balancer; the load balancer reaches only the application instances; the application reaches only the database. The application and database tiers have no route in from the internet at all.

Under test, terminating an application instance by hand left the site serving continuously, and its replacement reached a healthy state in about four minutes.

---

## Current status

### Built

- A custom VPC spanning two Availability Zones, with public and private subnets in each. Private subnets are associated with their own route tables so they cannot inherit an internet route.

- The application and database tiers can reach the internet outbound, for package updates, but have no inbound path from it. One NAT gateway per zone, and S3 traffic bypasses it entirely through a gateway endpoint.

- Three security groups, one per tier. Each tier's inbound rule names the security group above it rather than an address range, so the only way to reach the application instances is through the load balancer, and the only way to reach the database is through an application instance. Because instances are created and destroyed constantly, there is no address list to keep up to date and no window where a stale rule still allows traffic.

- An internet-facing Application Load Balancer with a listener on port 80 and a target group — one stable public address for a set of servers that keeps changing. The load balancer withholds traffic from any instance that stops answering.

- An Auto Scaling group across both zones, which replaces unhealthy instances automatically. Tested by terminating an instance by hand: the site stayed up throughout, and the replacement reached a healthy state in roughly four minutes.

- Terraform state held in S3 — encrypted, versioned, and locked against concurrent runs — created and managed by a separate Terraform project in `bootstrap/`.

### Not built yet

- **RDS PostgreSQL database** — in the private subnets, holding the application's data so it outlives any individual instance. Deployed Multi-AZ, so AWS keeps a standby in the other Availability Zone and fails over to it automatically. The standby is not readable; Multi-AZ buys availability, not read capacity.

- **S3 uploads bucket** — to allow uploads from any instance, including ones that do not exist yet, with durable and shared storage, reached through the gateway endpoint rather than the NAT gateways. An IAM role attached to the instances lets them write to the bucket without any access keys on the servers.

- **CloudWatch alarms** — to cover what the automation cannot resolve on its own. The load balancer withholds traffic and the Auto Scaling group replaces instances, but neither tells anyone, so without alarms there is potential for silently unresolved issues.

---

## Architecture

```
                              user
                                │
                                │  HTTP :80
                                ▼
                    ┌───────────────────────┐
                    │   Internet Gateway    │
                    └───────────┬───────────┘
 ┌──────────────────────────────┼─────────────────────────────────┐
 │ VPC  10.0.0.0/16             │                                 │
 │                              ▼                                 │
 │  PUBLIC SUBNETS    ┌─────────────────────────────┐             │
 │  10.0.1.0/24  (A)  │  Application Load Balancer  │             │
 │  10.0.2.0/24  (B)  │  listener :80 → target grp  │             │
 │                    └──────────────┬──────────────┘             │
 │    ┌──────────┐ ┌──────────┐      │                            │
 │    │ NAT gw A │ │ NAT gw B │      │  NEW connection, :80       │
 │    └────▲─────┘ └─────▲────┘      │                            │
 │         │             │           ▼                            │
 │  PRIVATE SUBNETS      │  ┌────────────────────────────┐        │
 │  10.0.11.0/24 (A)     └──┤  EC2 · Auto Scaling group  │        │
 │  10.0.12.0/24 (B)        │  one instance per zone     │        │
 │         └───────────────► │  httpd on :80              │        │
 │           outbound only   └──────┬──────────────┬──────┘       │
 │                                  │ :5432        │              │
 │                                  ▼              │              │
 │                    ┌─────────────────────────┐  │              │
 │                    │  RDS  PostgreSQL        │  │              │
 │                    │  Multi-AZ    (PLANNED)  │  │              │
 │                    └─────────────────────────┘  │              │
 └─────────────────────────────────────────────────┼──────────────┘
                                                   │ S3 gateway
                                                   ▼ endpoint (free)
                                       ┌─────────────────────────┐
                                       │  S3 uploads  (PLANNED)  │
                                       └─────────────────────────┘
```

The user's connection terminates at the load balancer, which opens its own separate connection to a chosen instance. The instance therefore never sees the visitor's IP address — it sees the load balancer's, which is why the application tier's security group references the load balancer's group rather than an address range.

---

## Decisions

### Networking

- **Three route tables, not two.** Both public subnets share one, because they send internet traffic to the same internet gateway. Each private subnet gets its own, because each routes to the NAT gateway in its own zone — a shared one would send a live zone's traffic through a dead one.

- **Private subnets are explicitly associated with their own route tables** rather than inheriting the VPC's main route table, so they cannot acquire an internet route that was not written intentionally.

- **One NAT gateway per zone.** Roughly double the cost, and it buys zone independence — a single shared gateway would reintroduce the point of failure the rest of the design removes.

- **An S3 gateway endpoint.** Free, and it avoids per-gigabyte NAT processing charges on what will be the largest traffic volume in the application.

### Security

- **The load balancer listens on port 80, not 443.** I do not have a domain, and therefore no TLS certificate. Stated as a known limitation rather than an oversight.

- **Security groups reference each other everywhere the far end is inside the design.** Outbound from the application tier is the one exception, because its destinations are public package repositories whose addresses cannot be enumerated. That is acceptable because security groups are stateful and the application tier has no inbound path from the internet.

- **The database security group has no outbound rule at all**, because a database does not need to initiate connections. Least privilege.

### Compute

- **Auto Scaling group: desired capacity 2, one instance per zone — and the minimum is also 2.** The floor matches the number of Availability Zones rather than the traffic, because a scaling policy optimises for its metric and knows nothing about zones. With a floor of 1 it could scale down to a single instance in a single zone overnight and silently undo the multi-zone design the rest of the architecture pays for.

- **Health check type `ELB`, not the default `EC2`.** The default only asks whether the instance is running, so an instance whose web server had died would be left in service while the load balancer withheld traffic from it — and the Auto Scaling group would report full healthy capacity the whole time.

- **The AMI comes from a data source, filtered by owner.** A pasted AMI ID is Region-specific and silently ages as Amazon republishes with security patches. Filtering by owner matters because anyone can publish an image with a matching name.

- **An extended health check grace period.** A new instance is correctly unhealthy while its user data installs a web server. Acting on that immediately would terminate it for failing a check it had not had time to pass, and do the same to its replacement — a launch-terminate loop.

### State

- **A separate Terraform project in `bootstrap/` creates and manages the S3 state bucket**, with versioning, encryption and public access blocking. Keeping it separate means `terraform destroy` in the main project cannot delete the bucket holding its own state.

### Terraform practice

- **`depends_on` on the NAT gateways.** Nothing in a NAT gateway block references the internet gateway, so Terraform's dependency graph has no reason to wait for it. This is the rare case where an explicit dependency is genuinely needed.

- **`vpc_endpoint_type = "Gateway"` written explicitly**, even though it is the default. That argument decides whether the endpoint is a free route table entry or a billed network interface — worth stating when a default changes the nature and cost of a resource rather than just a setting on it.

---

## Running it

Requires Terraform and AWS credentials configured locally.

```bash
cd bootstrap     # creates the S3 state bucket — run once, ever
terraform init
terraform apply

cd ..            # the application itself
terraform init
terraform apply
```

`terraform apply` from an empty AWS account produces a working, publicly reachable site. There are no manual steps at any point. The load balancer's address is printed as an output:

```
alb_dns_name = "three-tier-app-lb-1234567890.us-east-1.elb.amazonaws.com"
```

### If you want to run this yourself

The backend block in `provider.tf` points at my state bucket, which you cannot write to. Either change the `bucket` value to one of your own, or comment the `backend` block out entirely to use local state.

### Cost

Roughly **14 cents an hour** while running, in `us-east-1` — two NAT gateways, the load balancer, and two `t3.micro` instances. The NAT gateways are the largest item and they bill by the hour whether anything uses them or not.

```bash
terraform destroy
```

The state bucket in `bootstrap/` is deliberately left running; it costs a few cents a month and holds the state for everything else.