# organizations module

Creates and/or attaches AWS Organizations policies.

- If `create_policy = true`, the module creates the policy from a JSON file under `policies/`
- If `create_policy = false`, pass `policy_id` to attach an existing policy
