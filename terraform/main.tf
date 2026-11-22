terraform {
  required_version = ">= 0.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "lab-tf-state-vadym-2026"
    key            = "terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "lab-my-tf-lockid"
  }
}

provider "aws" {
  region = "eu-north-1"
}

variable "image_tag" {
  description = "Тег Docker-образу (хеш коміту GitHub)"
  type        = string
  default     = "latest"
}

# 1. Приватний реєстр Amazon ECR для Docker-образу
resource "aws_ecr_repository" "flask_repo" {
  name                 = "flask_app_repository"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# 2. Контейнерний сервіс Amazon Lightsail
resource "aws_lightsail_container_service" "flask_service" {
  name        = "flask-app-service"
  power       = "nano"
  scale       = 1
  is_disabled = false

  private_registry_access {
    ecr_image_puller_role {
      is_active = true
    }
  }
}

# 3. Дозвіл для Lightsail завантажувати образ із приватного ECR
resource "aws_ecr_repository_policy" "lightsail_pull_policy" {
  repository = aws_ecr_repository.flask_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLightsailPull"
        Effect = "Allow"
        Principal = {
          AWS = aws_lightsail_container_service.flask_service.private_registry_access[0].ecr_image_puller_role[0].principal_arn
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# 4. Розгортання контейнера з Flask-застосунком у Lightsail
resource "aws_lightsail_container_service_deployment_version" "flask_deployment" {
  service_name = aws_lightsail_container_service.flask_service.name

  container {
    container_name = "flask-app"
    image          = "${aws_ecr_repository.flask_repo.repository_url}:${var.image_tag}"

    ports = {
      "8080" = "HTTP"
    }
  }

  public_endpoint {
    container_name = "flask-app"
    container_port = 8080

    health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout_seconds     = 5
      interval_seconds    = 10
      path                = "/"
      success_codes       = "200-499"
    }
  }

  depends_on = [aws_ecr_repository_policy.lightsail_pull_policy]
}

output "ecr_repository_url" {
  description = "URL репозиторію в Amazon ECR"
  value       = aws_ecr_repository.flask_repo.repository_url
}

output "lightsail_service_url" {
  description = "Публічне HTTPS-посилання на розгорнутий застосунок"
  value       = aws_lightsail_container_service.flask_service.url
}