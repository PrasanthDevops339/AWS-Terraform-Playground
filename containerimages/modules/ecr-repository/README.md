# Private container repository

Native ECR repository, KMS encryption, immutable tags, access policy and lifecycle policy. Used because the supplied Platform modules directory has no ECR module and native-resource fallback was authorized.

For approved repositories, `organization_id` limits pull grants and `writer_arns` restricts publication. For staging, `reader_arns` limits image consumption; no organization-wide pull grant is added. The caller manages registry-level enhanced scanning and replication separately. Consumers also need `ecr:GetAuthorizationToken` in their identity policy.

Tagged approved releases are retained. Staging artifacts expire after 14 days; untagged approved artifacts after 30 days. `prevent_destroy` and `force_delete=false` protect retained images. Do not remove those protections to perform an ordinary rollback.

The module has no dependency on the original `Imagebuilder` repository. Its isolated mocked tests verify tag immutability, organization conditions and staging access policy.
