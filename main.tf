data "aws_ami" "linux2" { //linux ami
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.instance_class
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_grp.id
  vpc_security_group_ids = ["${aws_security_group.sg-wordpress.id}"]
  db_name                = var.database_name
  username               = var.database_user
  password               = var.database_password
  skip_final_snapshot    = true

  # to ignore rds manual password changes
  lifecycle {
    ignore_changes = [password]
  }

  tags = {
    Name = "wordpress_db"
  }
}
#USERDATA
data "template_file" "user_data" {
  template = file("${path.module}/user_data.tpl")
  vars = {
    db_username      = var.database_user
    db_user_password = var.database_password
    db_name          = var.database_name
    db_RDS           = aws_db_instance.wordpress_db.endpoint
  }
}
# Create EC2 ( only after RDS is provisioned-depends_on)
resource "aws_instance" "wordpress_server" {
  depends_on             = [aws_db_instance.wordpress_db]

  ami                    = data.aws_ami.linux2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.group2_public1.id
  vpc_security_group_ids = ["${aws_security_group.sg-wordpress.id}"]
  user_data              = data.template_file.user_data.rendered
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name = "Wordpress"
  }

  root_block_device {
    volume_size = var.root_volume_size

  }
}
# Sends your public key to the instance
resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = file(var.key_file)
}
# creating Elastic IP for EC2
resource "aws_eip" "eip" {
  instance = aws_instance.wordpress_server.id
}

output "IP" {
  value = aws_eip.eip.public_ip
}
output "RDS-Endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}
output "INFO" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://${aws_eip.eip.public_ip}"
}

resource "null_resource" "Wordpress_Installation_Waiting" {
  # trigger will create new null-resource if ec2 id or rds is changed
  triggers = {
    ec2_id       = aws_instance.wordpress_server.id,
    rds_endpoint = aws_db_instance.wordpress_db.endpoint

  }
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.private_key)
    host        = aws_eip.eip.public_ip
  }

 #Tail command below will check progress of WordPress Installation
  provisioner "remote-exec" {
    inline = ["sudo tail -f -n0 /var/log/cloud-init-output.log| grep -q 'WordPress Installed'"]

  }
}