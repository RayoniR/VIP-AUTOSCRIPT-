{# SSL/TLS Specific Template #}
{% extends "base.tpl" %}

{% block ssl_config %}
# SSL/TLS Configuration
[SSL]
certificate = """
-----BEGIN CERTIFICATE-----
{{ ssl_certificate }}
-----END CERTIFICATE-----
"""

private_key = """
-----BEGIN PRIVATE KEY-----
{{ ssl_private_key }}
-----END PRIVATE KEY-----
"""

ca_bundle = """
-----BEGIN CERTIFICATE-----
{{ ssl_ca_bundle }}
-----END CERTIFICATE-----
"""

tls_version = "{{ tls_version|default('1.3') }}"
ciphers = "{{ ssl_ciphers|default('ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384') }}"
session_cache = "{{ ssl_session_cache|default('builtin:1000') }}"
session_timeout = {{ ssl_session_timeout|default(3600) }}
ocsp_stapling = {{ ssl_ocsp_stapling|default(true) }}
hsts = {{ ssl_hsts|default(true) }}
{% endblock %}

{% block advanced_config %}
# Advanced SSL Settings
[ADVANCED_SSL]
sni_strict = {{ ssl_sni_strict|default(true) }}
alpn_strict = {{ ssl_alpn_strict|default(false) }}
early_data = {{ ssl_early_data|default(true) }}
keyless_ssl = {{ ssl_keyless|default(false) }}
zero_rtt = {{ ssl_zero_rtt|default(true) }}
{% endblock %}