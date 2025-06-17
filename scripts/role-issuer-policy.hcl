path "pki*" { 
  capabilities = ["create", "read", "update", "delete", "list", "sudo"] 
}

path "pki_int_ca*" { 
  capabilities = ["create", "read", "update", "delete", "list", "sudo"] 
}

path "pki_int_ca/roles/rh-custom-issuer" { 
  capabilities = ["create", "read", "update", "delete", "list", "sudo"] 
}

path "pki_int_ca/sign/rh-custom-issuer" { 
  capabilities = ["create", "read", "update", "delete", "list", "sudo"] 
}

path "pki_int_ca/issue/rh-custom-issuer" { 
  capabilities = ["create", "read", "update", "delete", "list", "sudo"] 
}
