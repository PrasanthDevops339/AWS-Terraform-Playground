###############################################################################
# Placeholder SAML signing identity
#
# The example previously shipped a static metadata.xml whose signing
# certificate had expired, so `terraform apply` failed inside Cognito. Instead
# of committing another certificate with a fixed expiry, the example mints a
# throwaway self-signed certificate on every run with the `tls` provider,
# renders the IdP metadata around it, and writes it to disk for the module to
# read. The module itself is unchanged.
#
# Nothing here is a real identity provider: the entity ID and SSO URL point at
# example.com, and the private key lives only in this example's state. Never
# reuse this pattern for a real federation setup.
###############################################################################

resource "tls_private_key" "saml_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "saml_signing" {
  private_key_pem = tls_private_key.saml_signing.private_key_pem

  subject {
    common_name  = local.saml_entity_id
    organization = "Terraform AWS Cognito Example"
  }

  # Long-lived on purpose: the point of generating it here is that the example
  # never goes stale the way the committed certificate did.
  validity_period_hours = 87600 # 10 years
  early_renewal_hours   = 720   # regenerate 30 days before expiry

  allowed_uses = [
    "digital_signature",
    "cert_signing",
  ]
}

locals {
  saml_entity_id = "https://idp.example.com/metadata"
  saml_sso_url   = "https://idp.example.com/sso"

  # SAML metadata carries the bare base64 DER body, without the PEM armor.
  saml_signing_certificate = replace(
    tls_self_signed_cert.saml_signing.cert_pem,
    "/-----(BEGIN|END) CERTIFICATE-----|\\n/",
    "",
  )

  saml_metadata = templatefile("${path.module}/files/metadata.xml.tftpl", {
    entity_id           = local.saml_entity_id
    sso_url             = local.saml_sso_url
    signing_certificate = local.saml_signing_certificate
  })
}

###############################################################################
# Hand the rendered metadata to the module
#
# The module reads its metadata from disk via `data "local_file"`, so the
# rendered XML has to become a real file first.
###############################################################################

resource "local_file" "saml_metadata" {
  filename = "${path.module}/generated/metadata.xml"
  content  = local.saml_metadata

  # Generated at apply time and gitignored - it is derived state, not source.
}
