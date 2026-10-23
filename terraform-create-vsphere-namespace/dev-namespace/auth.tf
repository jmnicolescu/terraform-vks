provider "restful" {
  alias    = "session"
  base_url = "https://${var.vcenter}"
  client = {
    tls_insecure_skip_verify = var.insecure_tls
  }
}

ephemeral "restful_resource" "vcenter_session" {
  provider             = restful.session
  path                 = "/api/session"
  method               = "POST"
  use_sensitive_output = true
  open_header = {
    Authorization = "Basic ${base64encode("${var.vcenter_user}:${var.vcenter_password}")}"
  }
  close_path   = "/api/session"
  close_method = "DELETE"
  close_header = {
    "vmware-api-session-id" = "$(body)"
  }
}

provider "restful" {
  base_url = "https://${var.vcenter}"
  client = {
    tls_insecure_skip_verify = var.insecure_tls
  }
  header = {
    "vmware-api-session-id" = ephemeral.restful_resource.vcenter_session.sensitive_output
  }
}
