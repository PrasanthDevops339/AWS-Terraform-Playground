# Preserve the previous two-module layout if it was applied in this same state.
# No effect for new deployments. Keep the primary provider/account unchanged.
moved {
  from = module.patch_outcome_account.aws_iam_role.writer
  to   = module.primary.aws_iam_role.writer[0]
}

moved {
  from = module.patch_outcome_account.aws_iam_role_policy.writer
  to   = module.primary.aws_iam_role_policy.archive[0]
}
