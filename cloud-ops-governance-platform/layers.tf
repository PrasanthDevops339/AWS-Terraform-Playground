#-----------------------------------------------------layers.tf-----------------------------------------------------
# All layers should be created in this file.
# Layer build instructions
# To create a new layer you can repeat the pattern of existing.
# Find and replace the values that match the layer name. Between the aws_lambda_layer_version and null_resource those should match.
# You also need to go to the pip_layer_requirements directory and create a .txt file with the same name.
# Inside that file place the packages you want installed that should be created.
# To sequence the layer builds, you must also put a dependency in place for the layer above.
# Troubleshooting
# If a layer build fails due to a missing zip file, check the shell script output of the apply pipeline for a failed pip request, most likely due to a dependency issue.

# Generate rule_engine layer
resource "aws_lambda_layer_version" "rule_engine" {
  layer_name          = "rule_engine"
  filename            = "./rule_engine.zip"
  compatible_architectures = ["x86_64"]
  compatible_runtimes = [var.python_lambda_layer_runtime]
  skip_destroy        = false
  source_code_hash    = null_resource.generate_rule_engine.triggers.requirements_hash
  depends_on          = [null_resource.generate_rule_engine]
}

# null resource creates a zip file when the requirements file changes
resource "null_resource" "generate_rule_engine" {
  provisioner "local-exec" {
    command = "/bin/bash scripts/generate-layer.sh ${var.python_lambda_layer_runtime} rule_engine"
  }

  triggers = {
    requirements_hash = filemd5("${path.module}/pip_layer_requirements/rule_engine.txt")
  }

  depends_on = []
}

# Generate pysnow layer
resource "aws_lambda_layer_version" "pysnow" {
  layer_name          = "pysnow"
  filename            = "./pysnow.zip"
  compatible_architectures = ["x86_64"]
  compatible_runtimes = [var.python_lambda_layer_runtime]
  skip_destroy        = false
  source_code_hash    = null_resource.generate_pysnow.triggers.requirements_hash
  depends_on          = [null_resource.generate_pysnow]
}

resource "null_resource" "generate_pysnow" {
  provisioner "local-exec" {
    command = "/bin/bash scripts/generate-layer.sh ${var.python_lambda_layer_runtime} pysnow"
  }

  triggers = {
    requirements_hash = filemd5("${path.module}/pip_layer_requirements/pysnow.txt")
  }

  depends_on = [null_resource.generate_rule_engine]
}

# Generate pandas_numpy_xlsxwriter layer
resource "aws_lambda_layer_version" "pandas_numpy_xlsxwriter" {
  layer_name          = "pandas_numpy_xlsxwriter"
  filename            = "./pandas_numpy_xlsxwriter.zip"
  compatible_architectures = ["x86_64"]
  compatible_runtimes = [var.python_lambda_layer_runtime]
  skip_destroy        = false
  source_code_hash    = null_resource.generate_pandas_numpy_xlsxwriter.triggers.requirements_hash
  depends_on          = [null_resource.generate_pandas_numpy_xlsxwriter]
}

resource "null_resource" "generate_pandas_numpy_xlsxwriter" {
  provisioner "local-exec" {
    command = "/bin/bash scripts/generate-layer.sh ${var.python_lambda_layer_runtime} pandas_numpy_xlsxwriter"
  }

  triggers = {
    requirements_hash = filemd5("${path.module}/pip_layer_requirements/pandas_numpy_xlsxwriter.txt")
  }

  depends_on = [null_resource.generate_pysnow]
}

# Generate advanced_python_wrapper_mysql layer
resource "aws_lambda_layer_version" "advanced_python_wrapper_mysql" {
  layer_name          = "advanced_python_wrapper_mysql"
  filename            = "./advanced_python_wrapper_mysql.zip"
  compatible_architectures = ["x86_64"]
  compatible_runtimes = [var.python_lambda_layer_runtime]
  skip_destroy        = false
  source_code_hash    = null_resource.generate_advanced_python_wrapper_mysql.triggers.requirements_hash
  depends_on          = [null_resource.generate_advanced_python_wrapper_mysql]
}

resource "null_resource" "generate_advanced_python_wrapper_mysql" {
  provisioner "local-exec" {
    command = "/bin/bash scripts/generate-layer.sh ${var.python_lambda_layer_runtime} advanced_python_wrapper_mysql"
  }

  triggers = {
    requirements_hash = filemd5("${path.module}/pip_layer_requirements/advanced_python_wrapper_mysql.txt")
  }

  depends_on = [null_resource.generate_pandas_numpy_xlsxwriter]
}

# Generate otel layer
resource "aws_lambda_layer_version" "otel" {
  layer_name          = "otel"
  filename            = "./otel.zip"
  compatible_architectures = ["x86_64"]
  compatible_runtimes = [var.python_lambda_layer_runtime]
  skip_destroy        = false
  source_code_hash    = null_resource.generate_otel.triggers.requirements_hash
  depends_on          = [null_resource.generate_otel]
}

resource "null_resource" "generate_otel" {
  provisioner "local-exec" {
    command = "/bin/bash scripts/generate-layer.sh ${var.otel_python_lambda_layer_runtime} otel"
  }

  triggers = {
    requirements_hash = filemd5("${path.module}/pip_layer_requirements/otel.txt")
  }

  depends_on = [null_resource.generate_advanced_python_wrapper_mysql]
}
