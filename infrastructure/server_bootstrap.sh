#!/bin/bash

groupadd security

useradd --create-home --home-dir /home/shenanigansd --shell /bin/bash --groups sudo,security --user-group shenanigansd
echo "shenanigansd:shadow" | chpasswd
mkdir /home/shenanigansd/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQ2s5V2xGbjaZ1qxshh5wwSPDYCc1/mIZy1Dy8WRD40 bradley.reynolds@darbia.dev" >/home/shenanigansd/.ssh/authorized_keys
chown -R shenanigansd:shenanigansd /home/shenanigansd/.ssh
chmod 700 /home/shenanigansd/.ssh
chmod 600 /home/shenanigansd/.ssh/authorized_keys

useradd --create-home --home-dir /home/syrup --shell /bin/bash --groups sudo,security --user-group syrup
echo "syrup:shadow" | chpasswd
mkdir /home/syrup/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz35ctr3dHnoqH64p/GOI4LVFrBnBYiBfbyXCBqftF1SBYBg4EAHRj5gK57UI0vI/G9+RnBYNysp6KYzENkd7Cjy02S5vmj7yZS/cdgqWYI4FiuzFok+ZvU8XCuDWal/zJAzTIl+eHUC1b18LXa+hxnnv6x4gVGZzIv5NpZXsD5KOmyfIxIlSNYs96AtwwRRq2XWM7t/LGdLbxPFor6576IQvEPH2Pgy/jdrUG6z0Y1nX6ePpV/n1f7Nun7yWKt2NRwerE+hb+9PC0Iw30eXiT47uwyiWhiMhfYsiH0HjATAS9MwwhYV+knfRnRskZir3Nh8AfusCGE8maAZSbOyaUWGJ2SwPHlbIYxGjzGpkL/aiPc8je2rxzIMeqWYWIy5AIvHyz9zKjDvVu+QDbY9+XA5dKwpsc7lh5KG6soLjFmN1FRTlHmhDZ+CfUF6oJjb/ykHlheSvMIb6wNe894IWO3FKhk8bxc924Ycr6nOlgIAozy9UbSxGlLqQULJ7rbTc= syru@SyruDesk" >/home/syrup/.ssh/authorized_keys
chown -R syrup:syrup /home/syrup/.ssh
chmod 700 /home/syrup/.ssh
chmod 600 /home/syrup/.ssh/authorized_keys

mkdir /opt/soc
chown shenanigansd:security /opt/soc
chmod g+w /opt/soc
