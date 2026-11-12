
#!/usr/bin/env bash
set -euo pipefail

# Project root (one level above scripts/)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

SSH_KEY="$HOME/.ssh/todo-app-key.pem"
REPO_URL="https://github.com/yar-portfolio/CICD-todoApp.git"
REMOTE_DIR="/home/ubuntu/CICD-todoApp"

echo "=== Reading Terraform outputs ==="

ANSIBLE_IP=$(terraform -chdir="$TF_DIR" output -raw ansible_controller_public_ip)

JENKINS_CONTROLLER_IP=$(terraform -chdir="$TF_DIR" output -raw jenkins_controller_private_ip)

JENKINS_AGENT_IP=$(terraform -chdir="$TF_DIR" output -raw jenkins_agent_private_ip)

SONARQUBE_IP=$(terraform -chdir="$TF_DIR" output -raw sonarqube_private_ip)

echo "Ansible Controller: $ANSIBLE_IP"

echo "=== Generating Ansible inventory ==="

TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TEMP_DIR:?}"' EXIT

cat > "$TEMP_DIR/hosts.ini" <<EOF
[jenkins_controller]
jenkins-controller ansible_host=$JENKINS_CONTROLLER_IP

[jenkins_agents]
jenkins-agent ansible_host=$JENKINS_AGENT_IP

[sonarqube]
sonarqube-server ansible_host=$SONARQUBE_IP

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
EOF

echo "=== Checking SSH agent ==="

ssh-add -l >/dev/null || {
    echo "Load your SSH key into ssh-agent first."
    exit 1
}

echo "=== Waiting for Ansible Controller ==="

ssh -A -i "$SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    "ubuntu@$ANSIBLE_IP" \
    'cloud-init status --wait'

echo "=== Cloning or updating repository ==="

ssh -A -i "$SSH_KEY" \
    "ubuntu@$ANSIBLE_IP" \
    bash -s -- "$REMOTE_DIR" "$REPO_URL" <<'EOF'
set -e

REMOTE_DIR="$1"
REPO_URL="$2"

if [ ! -d "$REMOTE_DIR/.git" ]; then
    git clone --branch main "$REPO_URL" "$REMOTE_DIR"
else
    git -C "$REMOTE_DIR" pull --ff-only origin main
fi
EOF

echo "=== Uploading Ansible inventory ==="

scp -i "$SSH_KEY" \
    "$TEMP_DIR/hosts.ini" \
    "ubuntu@$ANSIBLE_IP:$REMOTE_DIR/ansible/inventory/hosts.ini"

echo "=== Running Ansible Playbook ==="

ssh -A -i "$SSH_KEY" \
    "ubuntu@$ANSIBLE_IP" \
    "cd '$REMOTE_DIR/ansible' && \
     ansible-inventory -i inventory/hosts.ini --graph && \
     ansible-playbook -i inventory/hosts.ini playbooks/site.yml"

echo "=== Ansible configuration completed ==="

