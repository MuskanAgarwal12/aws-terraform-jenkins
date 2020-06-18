provider "aws" {
  region  = "ap-south-1"
  profile = "task1"
}

resource "aws_security_group" "sec-grp" {
  name        = "sec_grp"
  description = "Allow TLS inbound traffic"

  ingress {
    description = "TCP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]


  }

  tags = {
    Name = "sec-grp"
  }
}


resource "tls_private_key" "k1"{
  algorithm = "RSA"
}
resource "aws_key_pair" "mykey"{
  key_name   = "mykey"
  public_key = tls_private_key.k1.public_key_openssh
}

resource "local_file" "key-file"{
  content = tls_private_key.k1.private_key_pem
  filename = "mykey.pem"
}


resource "aws_instance" "instance" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.mykey.key_name
  security_groups= [ aws_security_group.sec-grp.name]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.k1.private_key_pem
    host     = aws_instance.instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
tags = {
    Name = "instance"
  }
}

resource "aws_ebs_volume" "ebs" {
  availability_zone = "${aws_instance.instance.availability_zone}"
  size              = 1

  tags = {
    Name = "ebs1"
  }
}

resource "aws_volume_attachment" "ebs-att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs.id}"
  instance_id = "${aws_instance.instance.id}"
  force_detach = true
}  

resource "null_resource" "nullvol"{
   depends_on = [
     aws_volume_attachment.ebs-att
     ]


    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =tls_private_key.k1.private_key_pem
    host     = "${aws_instance.instance.public_ip}"
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/MuskanAgarwal12/aws-terraform-jenkins.git /var/www/html"
      
    ]
  }
}




resource "aws_s3_bucket" "s3" {
  bucket = "s3bucks3"
  acl    = "public-read"

  tags = {
    Name = "s3"
  }
}

resource "aws_s3_bucket_object" "s3-object" {
  bucket = aws_s3_bucket.s3.bucket
  key    = "terraform1.png"
  source = "C://Users/Dell/Desktop/terraform1.png"
  acl = "public-read"
}

output "myoutput" {
           value = aws_s3_bucket.s3
}






resource "aws_cloudfront_distribution" "s3-distribution" {
  origin {
    domain_name = "${aws_s3_bucket.s3.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.s3.id}"
  
    }
  

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "web distribution"
  

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.s3.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

   restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN", "US"]
    }
  }

  tags = {
    Name = "web_distribution"
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.k1.private_key_pem
    host        = aws_instance.instance.public_ip
}




  provisioner "remote-exec" {
        inline  = [
            "sudo su <<END",
            "sudo echo \"<img src=\"https://${aws_cloudfront_distribution.s3-distribution.domain_name}/${aws_s3_bucket_object.s3-object.key}\">\" >> /var/www/html/index.html",
            "END"
            ]
    }
}


resource "null_resource" "ip"{
  provisioner  "local-exec"{
  command = "echo The IP is ${aws_instance.instance.public_ip} >> ip.txt"
 }
}


resource "aws_ebs_snapshot" "snapshot" {
  volume_id   = "${aws_ebs_volume.ebs.id}"
  description = "Snapshot of the EBS volume"
  
  tags = {
    env = "Production"
  }
  depends_on = [
    aws_volume_attachment.ebs-att
  ]
}



resource "null_resource" "website"{

 depends_on = [
   null_resource.nullvol , aws_instance.instance , aws_cloudfront_distribution.s3-distribution
   ]

  provisioner  "local-exec"{
  command = " start chrome ${aws_instance.instance.public_ip}"
 }
}
