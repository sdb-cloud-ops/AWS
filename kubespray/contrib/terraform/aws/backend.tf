terraform {
  backend "s3" {
    bucket = "ss-backend-config"
    key    = "dev/kubespray"
    region = "us-east-1"
  }
}