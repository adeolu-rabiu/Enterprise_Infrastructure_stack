# Phase 1 — Troubleshoot & Health Check Commands

This guide helps you validate and debug Phase 1 (Vagrant + VirtualBox + Terraform lab).
Run commands from your project root unless noted otherwise.

---

## 0) Quick Checklist (what “good” looks like)
- 7 VMs **running** (`vagrant status`)
- Each VM has expected IP:
  - masters: `192.168.100.11/12/13`
  - workers: `192.168.100.21/22/23`
  - infra:   `192.168.100.50`
- SSH OK to all VMs (`vagrant ssh <node> -c 'echo ok'`)
- Ping matrix from `master-1` = **OK** to all others
- `terraform validate` passes

---

## 1) Repository & Structure

```bash
# Show repo layout (2 levels)
tree -a -L 2

# Ensure Vagrantfile present and tracked
ls -lh Vagrantfile
git status

# Confirm you’re at the repo root (prints path)
git rev-parse --show-toplevel


2) VirtualBox Host-Only Network Allowlist

VirtualBox must allow 192.168.100.0/24.

# View/ensure allowlist (expect to see these two lines)
cat /etc/vbox/networks.conf

# If missing, add them:
sudo mkdir -p /etc/vbox
echo "* 192.168.100.0/24" | sudo tee -a /etc/vbox/networks.conf
echo "* fe80::/10"        | sudo tee -a /etc/vbox/networks.conf

# Inspect host-only interfaces
VBoxManage list hostonlyifs


3) Vagrant / VM Lifecycle
# Show VM states
vagrant status

# Create/boot all VMs
vagrant up

# Re-provision a specific VM (re-run inline shell/ansible provisioners)
vagrant provision master-1

# SSH config (diagnose login issues)
vagrant ssh-config

# List VMs known by VirtualBox (outside Vagrant)
VBoxManage list vms
VBoxManage list runningvms


UID mismatch fix (if you ever ran sudo vagrant up):

# Destroy root-owned env and remove local metadata as root
sudo -i
cd /home/<youruser>/Enterprise_Infrastructure_stack
vagrant destroy -f || true
rm -rf .vagrant
exit

# Ensure project files owned by your user
cd ~/Enterprise_Infrastructure_stack
sudo chown -R "$USER:$USER" .

# Remove any stray VBox VMs you don’t need
VBoxManage controlvm "<vm name>" poweroff || true
VBoxManage unregistervm "<vm name>" --delete || true

# (Optional) Clear global Vagrant metadata (keeps boxes/plugins)
rm -rf ~/.vagrant.d/data ~/.vagrant.d/tmp

# Recreate as your user (no sudo)
vagrant up


4) Networking & IP Verification
# Show IPs per node (expected: 192.168.100.x)
for n in master-1 master-2 master-3 worker-1 worker-2 worker-3 infra; do
  echo ">>> $n"
  vagrant ssh "$n" -c "hostname -I"
done

# Ping matrix from master-1 to all peers
vagrant ssh master-1 -c '
for ip in 192.168.100.12 192.168.100.13 192.168.100.21 192.168.100.22 192.168.100.23 192.168.100.50; do
  echo -n "$ip "; ping -c1 -W1 $ip >/dev/null && echo OK || echo FAIL
done'

# Inspect NICs in guest
vagrant ssh master-1 -c "ip addr show"

# Guest firewall (disable for lab)
vagrant ssh master-1 -c "sudo ufw status"
vagrant ssh master-1 -c "sudo ufw disable || true"



5) SSH & Access
# Simple SSH test to every VM
for n in master-1 master-2 master-3 worker-1 worker-2 worker-3 infra; do
  echo ">>> $n"
  vagrant ssh "$n" -c "echo ok-from-$(hostname)"
done

# If SSH fails, print Vagrant’s computed SSH settings
vagrant ssh-config


6) Terraform Hygiene
cd terraform

# Format all *.tf
terraform fmt -recursive

# Init providers without touching backends/state
terraform init -backend=false -input=false -upgrade

# Validate configuration
terraform validate

# Optional: dry-run plan (will use whatever provider is specified)
terraform plan

# Go back to repo root
cd ..



7) Logs & Deep Debug
# Verbose Vagrant bring-up (captures to file)
vagrant up --debug | tee vagrant-debug.log

# Show VirtualBox VM log (replace VM name)
VBoxManage showvminfo "homelab-master-1" --details

# Host resource checks
df -h
free -m
egrep -c '(vmx|svm)' /proc/cpuinfo        # virtualization support
lsmod | grep -E 'vbox|kvm'                # kernel modules present?



8) Clean Rebuild (Nuke & Recreate)
# From project root
vagrant destroy -f
rm -rf .vagrant

# (Optional) remove the cached box to force re-download next up
# vagrant box list
# vagrant box remove ubuntu/focal64 --provider virtualbox

# Bring everything back
vagrant up



9) Common Errors & Quick Fixes

Error: The IP address configured for the host-only network is not within the allowed ranges
Fix: Add to /etc/vbox/networks.conf:

echo "* 192.168.100.0/24" | sudo tee -a /etc/vbox/networks.conf


Error: The VirtualBox VM was created with a user that doesn't match the current user
Fix: Destroy as root + remove .vagrant, then recreate as your user (see UID mismatch fix above).

Error: Pings fail between nodes
Fix: Disable UFW in guests, confirm IPs, ensure host-only network exists and doesn’t overlap.

Error: terraform fmt check failed
Fix: cd terraform && terraform fmt -recursive

Error: VirtualBox driver missing (/dev/vboxdrv)
Fix (host):

sudo apt install -y dkms build-essential linux-headers-$(uname -r) virtualbox-dkms
sudo modprobe vboxdrv



10) One-Command Phase-1 Test (from repo root)
./scripts/test-phase1.sh --up


This will:

Ensure VirtualBox allowlist contains 192.168.100.0/24

Bring up VMs if needed

Verify IPs, SSH, ping matrix

Run Terraform fmt/init/validate

Print a pass/fail summary
