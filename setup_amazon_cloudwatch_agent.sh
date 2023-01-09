#! /bin/bash

set -eu

# Disable needrestart messages
cat << 'EOF' > /etc/needrestart/conf.d/restart.conf
$nrconf{kernelhints} = '0';
$nrconf{restart} = 'a';
EOF

apt update
apt upgrade -y

# Install collectD
curl -OL https://launchpad.net/ubuntu/+archive/primary/+files/collectd-core_5.12.0-11_amd64.deb
curl -OL https://launchpad.net/ubuntu/+archive/primary/+files/collectd_5.12.0-11_amd64.deb
apt install -y ./collectd-core_5.12.0-11_amd64.deb ./collectd_5.12.0-11_amd64.deb
rm -rf ./collectd-core_5.12.0-11_amd64.deb ./collectd_5.12.0-11_amd64.deb

# Install CloudWatch agent
curl -OL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
rm -rf ./amazon-cloudwatch-agent.deb

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
