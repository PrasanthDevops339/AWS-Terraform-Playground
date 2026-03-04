resource "aws_ecs_cluster" "ecs_cluster" {
  name = "prasanthins-operations-${var.environment}-ccop-ingest-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
