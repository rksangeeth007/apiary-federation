/**
 * Copyright (C) 2018-2019 Expedia Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

resource "aws_security_group" "endpoint_sg" {
  name   = "${local.instance_alias}-endpoint"
  vpc_id = var.vpc_id
  tags   = var.tags

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.waggledance_vpc.cidr_block]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.wd_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "remote_metastores" {
  count              = length(var.remote_metastores)
  vpc_id             = var.vpc_id
  vpc_endpoint_type  = "Interface"
  service_name       = var.remote_metastores[count.index].endpoint
  subnet_ids         = split(",", lookup(var.remote_metastores[count.index], "subnets", join(",", var.subnets)))
  security_group_ids = [aws_security_group.endpoint_sg.id]
  tags               = merge(map("Name", "${var.remote_metastores[count.index].prefix}_metastore"), var.tags)
}

data "template_file" "remote_metastores_yaml" {
  count    = length(var.remote_metastores)
  template = file("${path.module}/templates/waggle-dance-federation-remote.yml.tmpl")

  vars = {
    prefix             = var.remote_metastores[count.index].prefix
    metastore_host     = aws_vpc_endpoint.remote_metastores[count.index].dns_entry[0].dns_name
    metastore_port     = lookup(var.remote_metastores[count.index], "port", "9083")
    mapped_databases   = lookup(var.remote_metastores[count.index], "mapped-databases", "")
    writable_whitelist = lookup(var.remote_metastores[count.index], "writable-whitelist", "")
  }
}

data "template_file" "local_metastores_yaml" {
  count    = length(var.local_metastores)
  template = file("${path.module}/templates/waggle-dance-federation-local.yml.tmpl")

  vars = {
    prefix             = var.local_metastores[count.index].prefix
    metastore_host     = var.local_metastores[count.index].host
    metastore_port     = lookup(var.local_metastores[count.index], "port", "9083")
    mapped_databases   = lookup(var.local_metastores[count.index], "mapped-databases", "")
    writable_whitelist = lookup(var.local_metastores[count.index], "writable-whitelist", "")
  }
}

resource "aws_route53_zone" "remote_metastore" {
  count = var.enable_remote_metastore_dns == "" ? 0 : 1
  name  = "${local.remote_metastore_zone_prefix}-${var.aws_region}.${var.domain_extension}"
  tags  = var.tags

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "metastore_alias" {
  count   = var.enable_remote_metastore_dns == "" ? 0 : length(var.remote_metastores)
  zone_id = aws_route53_zone.remote_metastore[0].zone_id
  name    = var.remote_metastores[count.index].prefix
  type    = "CNAME"
  ttl     = "60"
  records = [aws_vpc_endpoint.remote_metastores[count.index].dns_entry[0].dns_name]
}
