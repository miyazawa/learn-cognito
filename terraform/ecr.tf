# Container registry for the application image.
# The repository is created by Terraform; the image is built and pushed by `make push`.
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE" # lets `latest` be overwritten on every push

  # Delete the repository even if it still contains images (learning environment)
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep storage small: only the 5 most recent images are retained
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
