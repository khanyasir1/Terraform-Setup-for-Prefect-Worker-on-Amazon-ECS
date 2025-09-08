output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.prefect.arn
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.prefect_service.name
}

output "prefect_secret_arn" {
  description = "Prefect API secret ARN (created or provided)"
  value       = local.secret_arn
  # Outputs the actual ARN of the secret used—helpful for reference and debugging.
}

output "secret_arn_local" {
  value = local.secret_arn
}




