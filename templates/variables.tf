variable "example_variable" {
  description = "Description of the variable"
  type        = string
  default     = "default_value"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}