# Terraform Training

```
ssh-keygen -t rsa -f terraform-training.rsa -N 'your passphrase'
terraform init -backend-config=main.tfbackend
terraform plan -var-file=main.tfvars
terraform apply -var-file=main.tfvars
ssh -i ./terraform-training.rsa ubuntu@your-instance-public-ip
```

```
# Rename, copy and edit the file.
cp ansible/inventory/staging.yml.sample ansible/inventory/staging.yml
ansible-playbook -i ansible/inventory/staging.yml ansible/site.yml
```
