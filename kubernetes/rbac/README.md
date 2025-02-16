# Kubernetes RBAC

## Create a user

> [!IMPORTANT]
> Make sure to set the `kubectl` context to the cluster to which you want to add the user!

```bash
./create_user.py <user> -g <group>
```

This will,

1. Create a private key for the user
2. Provision a client certificate for the user using the private key
3. Grant the permissions for the requested groups to the user
4. Generate a kubeconfig using the private key, and the client certificate for use with `kubectl`

### Examples

1. Create a user `foo` with group `vipyrsec`

```bash
./create_user.py foo -g vipyrsec
```

1. Create a user `bar` with groups `vipyrsec`, and `vipyrsec-core-devs` with a day's validity

```bash
./create_user.py bar -g vipyrsec -g vipyrsec-core-devs --expiry-seconds 86400
```

## Revoke a user's access granted by a specific role

> [!IMPORTANT]
> Make sure to set the `kubectl` context to the cluster from which you want to revoke the user's access!

```bash
kubectl delete clusterrolebinding <user>@<group>
```

### Example

Revoke user `foo`'s access granted by `vipyrsec-core-devs`

```bash
kubectl delete clusterrolebinding foo@vipyrsec-core-devs
```

## Revoke all permissions granted to a user (AKA, delete the user)

> [!IMPORTANT]
> Make sure to set the `kubectl` context to the cluster from which you want to revoke the user's access!

```bash
kubectl delete clusterrolebinding -luser=<user>
```

### Example

Revoke all permissions granted to user `foo`

```bash
kubectl delete clusterrolebinding -luser=foo
```
