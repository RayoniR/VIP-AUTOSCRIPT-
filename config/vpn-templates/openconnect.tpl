<?xml version="1.0" encoding="UTF-8"?>
<config auth="cert" client_cert_path="{{CLIENT_CERT_PATH}}" client_key_path="{{CLIENT_KEY_PATH}}">
  <server>{{SERVER_IP}}</server>
  <port>443</port>
  <protocol>anyconnect</protocol>
  <user>{{USERNAME}}</user>
  <passwd>{{PASSWORD}}</passwd>
  <reconnect>true</reconnect>
  <reconnect_timeout>30</reconnect_timeout>
  <mtu>1400</mtu>
  <dtls>true</dtls>
  <dtls_port>443</dtls_port>
  <dtls_ciphers>ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384</dtls_ciphers>
  <dtls_compression>false</dtls_compression>
  <ssl>true</ssl>
  <ssl_ciphers>ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384</ssl_ciphers>
  <ssl_compression>false</ssl_compression>
  <ssl_version>all</ssl_version>
  <ssl_renegotiation>true</ssl_renegotiation>
  <ssl_verify>true</ssl_verify>
  <ssl_verify_hostname>{{SERVER_SNI}}</ssl_verify_hostname>
  <ssl_trusted_ca>{{CA_CERT_PATH}}</ssl_trusted_ca>
  <ssl_pinning>true</ssl_pinning>
  <ssl_pinning_sha256>{{CERT_SHA256}}</ssl_pinning_sha256>
  <cookie>{{SESSION_COOKIE}}</cookie>
  <authgroup>{{AUTH_GROUP}}</authgroup>
  <server_cert_hash>{{SERVER_CERT_HASH}}</server_cert_hash>
  <csd>false</csd>
  <split_include>0.0.0.0/0</split_include>
  <split_exclude>192.168.0.0/16,10.0.0.0/8,172.16.0.0/12</split_exclude>
  <auto_reconnect>true</auto_reconnect>
  <auto_reconnect_timeout>60</auto_reconnect_timeout>
  <script>
    <![CDATA[
      #!/bin/bash
      case "$reason" in
        PRE_INIT)
          echo "Starting OpenConnect connection"
          ;;
        CONNECT)
          echo "Connected to VPN"
          ;;
        DISCONNECT)
          echo "Disconnected from VPN"
          ;;
      esac
    ]]>
  </script>
  <metadata>
    <generated>{{GENERATED_DATE}}</generated>
    <expires>{{EXPIRY_DATE}}</expires>
    <username>{{USERNAME}}</username>
    <server_id>{{SERVER_ID}}</server_id>
  </metadata>
</config>