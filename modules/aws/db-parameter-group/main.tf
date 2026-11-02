resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = var.family

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle { create_before_destroy = true }
}
