# soc-infrastructure

SOC infrastructure and IaC

## Stuff

To create a new role

```bash
ansible-galaxy init --offline <role name>
```

To run a playbook

```bash
ansible-playbook -i <inventory file> -k -K -u <remote user> <playbook name>
```

-k asks for ssh password
-K asks for sudo password (or type nothing to use ssh password)
