output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "The DNS name of the load balancer"
}

output "db_endpoint" {
  value = aws_db_instance.three_tier_app_db.endpoint
}
