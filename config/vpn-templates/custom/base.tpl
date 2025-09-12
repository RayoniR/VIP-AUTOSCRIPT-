# VIP-Autoscript Custom Configuration Template
# Template Engine: Jinja2
# Version: 3.1.0

{# Base template for all custom configurations #}
{% macro header() %}
# ==============================================================================
# VIP-AUTOSCRIPT CONFIGURATION
# Generated: {{ generated_date }}
# Expires: {{ expiry_date }}
# User: {{ username }}
# Server: {{ server_id }}
# Services: {{ services|join(', ') }}
# ==============================================================================
{% endmacro %}

{% macro network_config() %}
# Network Configuration
[NETWORK]
protocol = {{ protocol|default('tcp') }}
transport = {{ transport|default('tls') }}
port = {{ port|default(443) }}
sni = {{ sni|default(server_sni) }}
alpn = {{ alpn|default(['h2', 'http/1.1'])|join(',') }}
fingerprint = {{ fingerprint|default('chrome') }}
{% endmacro %}

{% macro authentication_config() %}
# Authentication
[AUTHENTICATION]
username = {{ username }}
password = {{ password }}
uuid = {{ uuid }}
flow = {{ flow|default('xtls-rprx-vision') }}
encryption = {{ encryption|default('none') }}
{% endmacro %}

{% macro routing_config() %}
# Routing Rules
[ROUTING]
domain_strategy = {{ domain_strategy|default('IPIfNonMatch') }}
rules = [
    {% for rule in routing_rules %}
    {
        "type": "{{ rule.type }}",
        "domain": [{{ rule.domains|map('quote')|join(', ') }}],
        "outboundTag": "{{ rule.outbound }}"
    }{% if not loop.last %},{% endif %}
    {% endfor %}
]
{% endmacro %}

{% macro performance_config() %}
# Performance Settings
[PERFORMANCE]
tcp_fast_open = {{ tcp_fast_open|default(true) }}
udp_fragment = {{ udp_fragment|default(true) }}
max_connections = {{ max_connections|default(1000) }}
buffer_size = {{ buffer_size|default(4096) }}
mtu = {{ mtu|default(1500) }}
{% endmacro %}

{% macro security_config() %}
# Security Settings
[SECURITY]
tls = {
    "allow_insecure": {{ tls_allow_insecure|default(false) }},
    "session_ticket": {{ tls_session_ticket|default(true) }},
    "reuse_session": {{ tls_reuse_session|default(true) }},
    "fingerprint": "{{ tls_fingerprint|default('randomized') }}"
}
firewall = {
    "bypass_local": {{ firewall_bypass_local|default(true) }},
    "bypass_china": {{ firewall_bypass_china|default(true) }},
    "block_ads": {{ firewall_block_ads|default(true) }}
}
{% endmacro %}

{# Main template rendering #}
{{ header() }}

{{ network_config() }}

{{ authentication_config() }}

{{ routing_config() }}

{{ performance_config() }}

{{ security_config() }}

# Advanced Settings
[ADVANCED]
obfuscation = {{ obfuscation_enabled|default(true) }}
multipath = {{ multipath_enabled|default(true) }}
compression = {{ compression_enabled|default(false) }}

# Services Status
[SERVICES]
ssh = {{ ssh_enabled }}
xray = {{ xray_enabled }}
bandwidth_limit = "{{ bandwidth_limit|default('2TB') }}"
concurrent_connections = {{ concurrent_connections|default(3) }}

# Metadata
[METADATA]
server_ip = "{{ server_ip }}"
server_sni = "{{ server_sni }}"
generated_date = "{{ generated_date }}"
expiry_date = "{{ expiry_date }}"
username = "{{ username }}"
server_id = "{{ server_id }}"
config_version = "3.1.0"