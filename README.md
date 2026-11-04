# Three-Tier Web Application on AWS

A load-balanced web application in a custom VPC spanning two Availability Zones, built entirely in Terraform — no console steps at any point.

Three tiers: a public load balancer, application servers in an Auto Scaling group, and a database. **Each tier can only be reached by the tier directly above it.** The internet reaches only the load balancer; the load balancer reaches only the application instances; the application reaches only the database. The application and database tiers have no route in from the internet at all.

Under test, stopping the web server on one instance — leaving the instance itself running — caused the Auto Scaling group to take it out of service and replace it, with the site serving continuously throughout.

---

## Current status

### Built

- A custom VPC spanning two Availability Zones, with public and private subnets in each. Private subnets are associated with their own route tables so they cannot inherit an internet route.

- The application and database tiers can reach the internet outbound, for package updates, but have no inbound path from it. One NAT gateway per zone, and S3 traffic bypasses it entirely through a gateway endpoint.

- Three security groups, one per tier. Each tier's inbound rule names the security group above it rather than an address range, so the only way to reach the application instances is through the load balancer, and the only way to reach the database is through an application instance. Naming the group rather than a range means the rule describes what a resource *is* rather than where it sits. Anything added to the private subnets later does not inherit database access simply by having an address there, and the rules do not go stale when the addressing changes.

- An internet-facing Application Load Balancer with a listener on port 80 and a target group — one stable public address for a set of servers that keeps changing. The load balancer withholds traffic from any instance that stops answering.

- An Auto Scaling group across both zones, which replaces unhealthy instances automatically. Tested by terminating an instance by hand: the site stayed up throughout, and the replacement reached a healthy state in roughly four minutes.

- Terraform state held in S3 — encrypted, versioned, and locked against concurrent runs — created and managed by a separate Terraform project in `bootstrap/`.

- An RDS PostgreSQL database in the private subnets, deployed Multi-AZ, holding the application’s working data. It is reachable only from the application tier, and not from the internet at all.

- An S3 bucket for uploads, written to by the application instances through an IAM role.
  No access keys exist anywhere in this project.

- Shell access to the private instances through SSM Session Manager. There is no SSH key
  pair, no bastion host, and no inbound rule on port 22 anywhere in the design.

- Four alarms delivered to email through an SNS topic: sustained unhealthy instances, database free
  storage running low, 5xx responses from the load balancer, and a monthly cost budget.

  - A CloudTrail trail recording all management API activity to its own S3 bucket, with log file
  validation enabled. It lives in `bootstrap/` and runs continuously.

- The CloudWatch agent on each instance, shipping the web server's access log to a CloudWatch log
  group with a seven-day retention. The hypervisor cannot see inside the operating system, so
  anything in a log file needs an agent to report it.

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
 │                    │  Multi-AZ               │  │              │
 │                    └─────────────────────────┘  │              │
 └─────────────────────────────────────────────────┼──────────────┘
                                                   │ S3 gateway
                                                   ▼ endpoint (free)
                                       ┌─────────────────────────┐
                                       │  S3 uploads             │
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

- **No VPC interface endpoints for Session Manager.** The agent only needs outbound HTTPS,
  which the NAT gateways already provide. Three interface endpoints would cost roughly $20 a
  month to replace something already paid for.

### Security

- **The load balancer listens on port 80, not 443.** I do not have a domain, and therefore no TLS certificate. Stated as a known limitation rather than an oversight.

- **Security groups reference each other everywhere the far end is inside the design.** Outbound from the application tier is the one exception, because its destinations are public package repositories whose addresses cannot be enumerated. That is acceptable because security groups are stateful and the application tier has no inbound path from the internet.

- **The database security group has no outbound rule at all**, because a database does not need to initiate connections. Least privilege.

- **The instances get their AWS permissions from a role, not from access keys.** A key would
  have to be written into the user data script, which is in this repository, and it would
  never expire. The role gives each instance temporary credentials that AWS rotates on its
  own, fetched from the instance metadata service. boto3 and the AWS CLI find them with no
  configuration, so nothing in the project stores a credential.

- **The role can write and read objects, and cannot list the bucket.** `PutObject` and
  `GetObject` act on objects, so the policy names the bucket ARN with `/*` on the end.
  Listing is a bucket-level action and is deliberately absent — the application has no
  reason to enumerate the bucket, so it cannot.

- **Shell access is through SSM Session Manager rather than SSH.** The agent on the instance
  connects outbound to AWS and AWS brokers the session, so administrative access to a private
  instance needs no inbound path, no key to distribute, and no bastion host to maintain.

  - **CloudTrail's permission is a bucket policy, not an identity policy.** Every other permission in
  this project is attached to an identity I control — the instance role. CloudTrail is an AWS
  service, so there is no role of mine to attach anything to, and the only place left to put the
  permission is on the bucket itself.

### Compute

- **Auto Scaling group: desired capacity 2, one instance per zone — and the minimum is also 2.** The floor matches the number of Availability Zones rather than the traffic, because a scaling policy optimises for its metric and knows nothing about zones. With a floor of 1 it could scale down to a single instance in a single zone overnight and silently undo the multi-zone design the rest of the architecture pays for.

- **Health check type `ELB`, not the default `EC2`.** The default only asks whether the instance is running, so an instance whose web server had died would be left in service while the load balancer withheld traffic from it — and the Auto Scaling group would report full healthy capacity the whole time.

Tested by stopping the web server rather than terminating the instance: terminating proves
  nothing, because the instance is gone either way. A running instance that serves nothing is
  the only case that distinguishes the two settings. The Auto Scaling group's own activity log
  recorded the reason — "an instance was taken out of service in response to an ELB system
  health check failure."

- **The AMI comes from a data source, filtered by owner.** A pasted AMI ID is Region-specific and silently ages as Amazon republishes with security patches. Filtering by owner matters because anyone can publish an image with a matching name.

- **An extended health check grace period.** A new instance is correctly unhealthy while its user data installs a web server. Acting on that immediately would terminate it for failing a check it had not had time to pass, and do the same to its replacement — a launch-terminate loop.

### Database

- **A database for the application's working data, and a bucket for uploaded files.** They answer
  different kinds of request. A bucket hands back a whole object when you ask for it by name. A
  database answers questions that have to be worked out from the data — "this customer's last ten
  orders, newest first" — and it handles several requests changing the same record at once, where
  S3 would replace the whole object and let the last write win.

- **Multi-AZ, which buys availability and not read capacity.** AWS keeps a standby copy in the
  other Availability Zone and fails over to it automatically. The standby cannot be read from — it
  is not a read replica — so this does nothing for query throughput. It roughly doubles the database
  cost, which is the honest price of the same zone independence the two NAT gateways pay for
  elsewhere.

### State

- **A separate Terraform project in `bootstrap/` creates and manages the S3 state bucket**, with versioning, encryption and public access blocking. Keeping it separate means `terraform destroy` in the main project cannot delete the bucket holding its own state.

- **The password comes from a variable marked `sensitive`, supplied through an environment variable
  rather than a file.** `sensitive` only hides the value from Terraform's output — the password is
  written into the state file in plain text regardless. That is the concrete reason the state bucket
  is encrypted, versioned and blocked from public access.

  - **`bootstrap/` holds everything account-level and permanent**, not just the state bucket: the cost
  budget and the CloudTrail trail as well. The main project is the application, and it is built and
  destroyed constantly. Anything whose job is to watch for problems cannot live there — a budget
  destroyed every evening cannot catch a stack left running overnight, and a trail that only runs
  while I am working only records while I am working.

- **The trail writes to its own bucket rather than the state bucket.** The state bucket holds a
  database password in plaintext, and adding a resource policy to it would mean one more thing to get
  wrong on the only bucket in the account containing a secret. Their retention needs are also
  opposite: state is versioned so old versions can be recovered, while trail logs only grow and
  should eventually expire.

### Terraform practice

- **`depends_on` on the NAT gateways.** Nothing in a NAT gateway block references the internet gateway, so Terraform's dependency graph has no reason to wait for it. This is the rare case where an explicit dependency is genuinely needed.

- **`vpc_endpoint_type = "Gateway"` written explicitly**, even though it is the default. That argument decides whether the endpoint is a free route table entry or a billed network interface — worth stating when a default changes the nature and cost of a resource rather than just a setting on it.

- **No deletion protection, no `prevent_destroy`, and `skip_final_snapshot = true`.** In production
  both guards would be on and nobody would run `terraform destroy`. Here the destroy *is* the
  operation — this stack is built and torn down every session — so a guard against teardown is a
  guard against me. `prevent_destroy` would be worse than inconvenient: it fails the whole plan, so
  nothing gets destroyed and the load balancer and NAT gateways keep billing.
  
  ### Observability

  - **Alarms exist because the automation is silent.** The load balancer withholds traffic from a failed
  instance and the Auto Scaling group replaces it, and neither tells anyone. A memory leak killing the
  web server every forty minutes would churn instances all night with the site technically up and nobody
  aware of it.

- **The unhealthy-instance alarm waits five minutes before firing.** A measured replacement takes about
  four minutes to reach a healthy state, so anything shorter fires on every routine replacement — and an
  alarm that cries wolf gets filtered into a folder nobody reads. The threshold comes from a number I
  measured rather than a default.

- **The load balancer's 5xx alarm fires on a single error.** With two instances, the load balancer only
  returns 5xx when it has no healthy target at all, which means both are down. That is not a condition
  worth tolerating, so the threshold is one.

- **Cost monitoring is an AWS Budget rather than a CloudWatch billing alarm.** Billing metrics exist in
  one Region only, update every six hours, and require billing alerts to be switched on by hand in the
  account settings. A budget needs no console step and can alarm on a forecast rather than waiting until
  the money is already spent.

  - **CloudTrail answers who did what, which is a different question from whether anything is wrong.**
  An alarm tells me an instance is unhealthy. CloudTrail tells me that at 17:18 the Auto Scaling
  service called `TerminateInstances`. Neither substitutes for the other.

- **A trail, even though AWS already records the last 90 days for free.** Every account keeps API
  activity in CloudTrail Event history with no setup at all. The trail does not turn recording on —
  it makes the record durable past 90 days and keeps it in a bucket I own.

- **The log group is created by Terraform rather than by the agent.** The agent has permission to
  create its own, and a group it creates defaults to never expiring — so it accumulates storage
  charges indefinitely and sits outside Terraform, where `destroy` will never find it.
---


## Running it

Requires Terraform and AWS credentials configured locally.

```bash
cd bootstrap     # creates the S3 state bucket — run once, ever
terraform init
terraform apply

cd ..            # the application itself
terraform init

export TF_VAR_db_password='choose-something'
export TF_VAR_alert_email='you@example.com'
# PowerShell: $env:TF_VAR_db_password = '...' and $env:TF_VAR_alert_email = '...'

terraform apply
```

Neither the database password nor the alert email address is in this repository, and neither has a default —
Terraform refuses to run without both. `TF_VAR_` followed by the variable name is how Terraform picks up any
variable from the environment.

The email address is a variable for a different reason than the password. It is not a secret; it simply is not
a property of the infrastructure. Anyone running this needs their own, the same way they need their own state
bucket.

After the apply, AWS sends a confirmation link for the SNS email subscription. **It has to be clicked before
any alarm email will arrive** — Terraform cannot confirm it.

`terraform apply` from an empty AWS account produces a working, publicly reachable site. The load balancer's
address is printed as an output:

```
alb_dns_name = "three-tier-app-lb-1234567890.us-east-1.elb.amazonaws.com"
```

### If you want to run this yourself

The backend block in `provider.tf` points at my state bucket, which you cannot write to. Either change the `bucket` value to one of your own, or comment the `backend` block out entirely to use local state.

### Cost

Roughly **18 cents an hour** while running, in `us-east-1` — two NAT gateways, the Application Load
Balancer, two `t3.micro` instances, and a Multi-AZ `db.t3.micro` database. The NAT gateways and the
database are the largest items, and both bill by the hour whether anything uses them or not.

Multi-AZ roughly doubles the database cost, because the standby is a second instance with its own storage.

```bash
terraform destroy
```

The state bucket in `bootstrap/` is deliberately left running; it costs a few cents a month and holds the
state for everything else.