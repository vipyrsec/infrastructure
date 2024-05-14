function create_user {
USER=$1
ROLE=$2

openssl genrsa -out $USER.key 2048

openssl req -new -key $USER.key \
    -subj "/C=DK/ST=DK/O=''/CN=$USER" \
    -out $USER.csr

# Extract the csr
REQ=$(cat $USER.csr | base64 | tr -d "\n")

# Create a Kubernetes CSR object and approve it
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USER
spec:
  groups:
  - system:authenticated
  request: $REQ
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
kubectl get csr
kubectl certificate approve $USER

# Extract the approved certificate
kubectl get csr $USER -o jsonpath='{.status.certificate}'| base64 -d > $USER.crt

# Bind user to a role
kubectl create clusterrolebinding $USER-binding --clusterrole=$ROLE --user=$USER

# Cleanup the CSR
kubectl delete csr $USER

# Make the config file
kubectl config set-credentials $USER --client-key=$USER.key --client-certificate=$USER.crt --embed-certs=true --kubeconfig="$USER.config"
}

create_user "$@"
