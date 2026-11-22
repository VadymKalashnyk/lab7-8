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

variable "lightsail_image" {
  description = "Ідентифікатор образу у внутрішньому сховищі Lightsail"
  type        = string
  default     = ""
}

# 1. Контейнерний сервіс Amazon Lightsail
resource "aws_lightsail_container_service" "flask_service" {
  name        = "flask-app-service"
  power       = "nano"
  scale       = 1
  is_disabled = false
}

# 2. Розгортання контейнера з Flask-застосунком
resource "aws_lightsail_container_service_deployment_version" "flask_deployment" {
  service_name = aws_lightsail_container_service.flask_service.name

  container {
    container_name = "flask-app"
    image          = var.lightsail_image

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
}

output "lightsail_service_url" {
  description = "Публічне HTTPS-посилання на розгорнутий застосунок"
  value       = aws_lightsail_container_service.flask_service.url
}