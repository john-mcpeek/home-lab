FROM  registry.k8s.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.46

USER root

# Update certificate store
# Fetch the server cert and place it in the CA certificates directory
RUN openssl s_client -servername pve.lab -connect 10.0.0.10:8006 </dev/null 2>/dev/null | \
    openssl x509 -outform PEM > /usr/local/share/ca-certificates/pve.lab.crt && \
    update-ca-certificates

RUN wget -P /home/imagebuilder https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso

USER imagebuilder
