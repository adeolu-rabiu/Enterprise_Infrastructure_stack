#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# Phase 0 Bootstrap: Choose Your Stack (Ubuntu)
# ===============================================

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script needs sudo. Re-run with: sudo $0" >&2
    exit 1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

apt_quiet() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -qq
}

ensure_pkg() { apt-get install -y "$@"; }

add_apt_keyring() {
  # usage: add_apt_keyring <url> <dest>
  curl -fsSL "$1" | gpg --dearmor | tee "$2" >/dev/null
}

install_core_utils() {
  echo ">> Installing core utilities..."
  apt_quiet
  ensure_pkg git curl wget unzip tar tree jq htop net-tools iproute2 ca-certificates gnupg lsb-release software-properties-common
  echo "✓ Core utilities installed."
}

install_virtualization() {
  echo ">> Installing VirtualBox & Vagrant..."
  apt_quiet
  ensure_pkg virtualbox vagrant
  echo "✓ VirtualBox: $(vboxmanage --version 2>/dev/null || echo 'installed')"
  echo "✓ Vagrant: $(vagrant --version 2>/dev/null || echo 'installed')"
}

install_docker() {
  echo ">> Installing Docker Engine & Compose..."
  apt_quiet
  ensure_pkg docker.io docker-compose
  systemctl enable --now docker
  usermod -aG docker "${SUDO_USER:-$USER}" || true
  echo "✓ Docker: $(docker --version 2>/dev/null || echo 'installed')"
  echo "✓ Docker Compose: $(docker-compose --version 2>/dev/null || echo 'installed')"
  echo "ℹ You may need to log out/in or run: newgrp docker"
}

install_terraform() {
  echo ">> Installing Terraform..."
  local codename; codename="$(lsb_release -cs)"
  install -d /usr/share/keyrings
  add_apt_keyring "https://apt.releases.hashicorp.com/gpg" "/usr/share/keyrings/hashicorp-archive-keyring.gpg"
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" > /etc/apt/sources.list.d/hashicorp.list
  apt_quiet
  ensure_pkg terraform
  echo "✓ $(terraform version | head -1)"
}

install_ansible() {
  echo ">> Installing Ansible..."
  apt_quiet
  add-apt-repository -y ppa:ansible/ansible
  apt_quiet
  ensure_pkg ansible
  echo "✓ $(ansible --version | head -1)"
}

install_kubernetes_cli() {
  echo ">> Installing kubectl & Helm..."
  # kubectl
  curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
  # helm
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "✓ kubectl: $(kubectl version --client --short 2>/dev/null || echo 'installed')"
  echo "✓ Helm: $(helm version --short 2>/dev/null || echo 'installed')"
}

install_awscli_v2() {
  echo ">> Installing AWS CLI v2..."
  apt_quiet; ensure_pkg unzip
  tmpdir="$(mktemp -d)"; pushd "$tmpdir" >/dev/null
  curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  unzip -q awscliv2.zip
  ./aws/install --update
  popd >/dev/null; rm -rf "$tmpdir"
  echo "✓ $(aws --version 2>/dev/null)"
}

install_gcloud() {
  echo ">> Installing Google Cloud SDK..."
  local codename; codename="$(lsb_release -cs)"
  install -d /usr/share/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor | tee /usr/share/keyrings/cloud.google.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk ${codename} main" > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt_quiet
  ensure_pkg google-cloud-cli
  echo "✓ gcloud: $(gcloud version | head -1 2>/dev/null || echo 'installed')"
}

install_azure_cli() {
  echo ">> Installing Azure CLI..."
  local codename; codename="$(lsb_release -cs)"
  install -d /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/keyrings/microsoft.gpg >/dev/null
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${codename} main" > /etc/apt/sources.list.d/azure-cli.list
  apt_quiet
  ensure_pkg azure-cli
  echo "✓ Azure CLI installed."
}

install_lazydocker() {
  echo ">> Installing lazydocker..."
  latest="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | jq -r '.tag_name')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) tarname="lazydocker_${latest#v}_Linux_x86_64.tar.gz" ;;
    aarch64|arm64) tarname="lazydocker_${latest#v}_Linux_arm64.tar.gz" ;;
    *) echo "Unsupported arch: $arch"; return 1 ;;
  esac
  tmpdir="$(mktemp -d)"; pushd "$tmpdir" >/dev/null
  curl -fsSLO "https://github.com/jesseduffield/lazydocker/releases/download/${latest}/${tarname}"
  tar -xzf "${tarname}"
  install lazydocker /usr/local/bin/lazydocker
  popd >/dev/null; rm -rf "$tmpdir"
  echo "✓ $(lazydocker --version 2>/dev/null || echo 'lazydocker installed')"
}

# -------- NEW: Local cluster tooling --------

install_minikube() {
  echo ">> Installing Minikube..."
  apt_quiet
  ensure_pkg conntrack
  curl -fsSLo /usr/local/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x /usr/local/bin/minikube
  echo "✓ $(minikube version 2>/dev/null || echo 'minikube installed')"
  echo "ℹ Start with: minikube start --driver=docker   (or virtualbox)"
}

install_kind() {
  echo ">> Installing kind (Kubernetes in Docker)..."
  curl -fsSLo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
  chmod +x ./kind
  mv ./kind /usr/local/bin/kind
  echo "✓ $(kind --version 2>/dev/null || echo 'kind installed')"
}

install_k9s() {
  echo ">> Installing k9s..."
  # Use latest release binary
  latest="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) tarname="k9s_Linux_amd64.tar.gz" ;;
    aarch64|arm64) tarname="k9s_Linux_arm64.tar.gz" ;;
    *) echo "Unsupported arch: $arch"; return 1 ;;
  esac
  tmpdir="$(mktemp -d)"; pushd "$tmpdir" >/dev/null
  curl -fsSLO "https://github.com/derailed/k9s/releases/download/${latest}/${tarname}"
  tar -xzf "${tarname}" k9s
  install k9s /usr/local/bin/k9s
  popd >/dev/null; rm -rf "$tmpdir"
  echo "✓ $(k9s version --short 2>/dev/null || echo 'k9s installed')"
}

install_kubectx_kubens() {
  echo ">> Installing kubectx + kubens..."
  apt_quiet
  ensure_pkg git
  if [[ ! -d /opt/kubectx ]]; then
    git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
  else
    git -C /opt/kubectx pull --ff-only || true
  fi
  ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
  ln -sf /opt/kubectx/kubens   /usr/local/bin/kubens
  echo "✓ kubectx: $(kubectx -h >/dev/null 2>&1 && echo installed || echo failed)"
  echo "✓ kubens:  $(kubens -h  >/dev/null 2>&1 && echo installed || echo failed)"
}

install_oc_cli() {
  echo ">> Installing OpenShift oc CLI..."
  tmpdir="$(mktemp -d)"; pushd "$tmpdir" >/dev/null
  curl -fsSLO https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz
  tar -xzf oc.tar.gz oc
  install oc /usr/local/bin/oc
  popd >/dev/null; rm -rf "$tmpdir"
  echo "✓ $(oc version --client 2>/dev/null || echo 'oc installed')"
}

show_menu() {
  cat <<'MENU'
Choose what to install (separate multiple choices with spaces):
  1) Core utilities (git, curl, wget, unzip, tar, tree, jq, htop, net-tools, iproute2)
  2) Virtualization (VirtualBox, Vagrant)
  3) Docker Engine & Compose
  4) Terraform
  5) Ansible
  6) Kubernetes CLIs (kubectl, Helm)
  7) AWS CLI v2
  8) Google Cloud SDK (gcloud)
  9) Azure CLI (az)
 10) lazydocker
 11) Minikube (local K8s; requires Docker or VirtualBox) 
 12) kind (Kubernetes in Docker)
 13) k9s (terminal UI for K8s)
 14) kubectx + kubens (fast context/namespace switch)
 15) OpenShift oc CLI
 99) EVERYTHING above
  0) Quit
MENU
  read -rp "Enter selection: " -a CHOICES
}

run_choice() {
  case "$1" in
    1) install_core_utils ;;
    2) install_virtualization ;;
    3) install_docker ;;
    4) install_terraform ;;
    5) install_ansible ;;
    6) install_kubernetes_cli ;;
    7) install_awscli_v2 ;;
    8) install_gcloud ;;
    9) install_azure_cli ;;
    10) install_lazydocker ;;
    11) install_minikube ;;
    12) install_kind ;;
    13) install_k9s ;;
    14) install_kubectx_kubens ;;
    15) install_oc_cli ;;
    99)
       install_core_utils
       install_virtualization
       install_docker
       install_terraform
       install_ansible
       install_kubernetes_cli
       install_awscli_v2
       install_gcloud
       install_azure_cli
       install_lazydocker
       install_minikube
       install_kind
       install_k9s
       install_kubectx_kubens
       install_oc_cli
       ;;
    0) echo "Bye!"; exit 0 ;;
    *) echo "Unknown option: $1" ;;
  esac
}

main() {
  need_sudo
  echo "=== Phase 0 Bootstrap (Ubuntu) ==="
  show_menu
  for c in "${CHOICES[@]:-}"; do
    run_choice "$c"
  done
  echo "=== Done. Tips ==="
  echo "- If you installed Docker: run 'newgrp docker' or re-login to use it without sudo."
  echo "- Minikube: 'minikube start --driver=docker' (or --driver=virtualbox)."
  echo "- kind: 'kind create cluster'."
  echo "- k9s: 'k9s' (needs KUBECONFIG)."
}

main "$@"

