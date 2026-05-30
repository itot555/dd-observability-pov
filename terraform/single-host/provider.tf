provider "aws" {
  region = var.region
}

provider "tls" {}

provider "local" {}

provider "null" {}

provider "random" {}
