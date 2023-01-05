# Terraform Training

```
ssh-keygen -t rsa -f terraform-training.rsa -N 'your passphrase'
terraform init -backend-config=main.tfbackend
terraform plan -var-file=main.tfvars
terraform apply -var-file=main.tfvars
ssh -i ./terraform-training.rsa ec2-user@your-instance-public-ip
```
