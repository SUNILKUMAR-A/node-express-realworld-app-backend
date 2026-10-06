// Non-secret connection metadata for the Lambda configuration.
output "vpc_id" {
  description = "VPC hosting the private database and application Lambda."
  value       = aws_vpc.app.id
}

output "lambda_security_group_id" {
  description = "Attach this security group to the application Lambda."
  value       = aws_security_group.lambda.id
}

output "secrets_manager_vpc_endpoint_id" {
  description = "Private interface endpoint Lambda uses to retrieve RDS-managed credentials."
  value       = aws_vpc_endpoint.secrets_manager.id
}

output "database_endpoint" {
  description = "Private PostgreSQL endpoint. It is reachable only from the Lambda security group."
  value       = aws_db_instance.app.address
}

output "database_port" {
  value = aws_db_instance.app.port
}

output "database_name" {
  value = aws_db_instance.app.db_name
}

output "database_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed master credentials."
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}
