include */Makefile.inc

LIMIT_MEMORY       ?= 10240
LIMIT_CPUS         ?= 4
NODES_COUNT        ?= 3
CLUSTER_NAME       ?= dgis-on-prem
CLUSTER_DOMAIN     ?= on-prem.loc
ON_PREMISE_VERSION ?= 1.7.0
HELM_TIMEOUT       ?= 900s

KAFKA_CHART_VERSION = 20.0.0

.ONESHELL:
.EXPORT_ALL_VARIABLES:
SHELL := /bin/bash

.DEFAULT_GOAL := dummy
dummy:
	@echo "Please specify valid target:"
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null \
	    | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
	    | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
	    | cat -n

create-cluster:
	minikube start --driver docker --memory $(LIMIT_MEMORY) --cpus $(LIMIT_CPUS) \
		--addons ingress,ingress-dns,storage-provisioner \
		--insecure-registry registry.$(CLUSTER_DOMAIN) \
		--nodes $(NODES_COUNT) -p $(CLUSTER_NAME)

remove-cluster:
	minikube delete -p dgis-on-prem

install-minio:
	helm repo add minio https://charts.min.io/
	helm upgrade -i --atomic --timeout $(HELM_TIMEOUT) on-prem-minio minio/minio -f <(envsubst < minio.values.yaml)

uninstall-minio:
	helm uninstall on-prem-minio

install-registry: create-registry-cert
	helm repo add twuni https://helm.twun.io
	helm upgrade -i --atomic --timeout $(HELM_TIMEOUT) on-prem-docker-registry twuni/docker-registry -f <(envsubst < registry.values.yaml)

uninstall-registry:
	helm uninstall on-prem-docker-registry

install-cassandra:
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm upgrade -i --atomic --timeout $(HELM_TIMEOUT) on-prem-cassandra bitnami/cassandra -f cassandra.values.yaml

uninstall-cassandra:
	helm uninstall on-prem-cassandra

install-kafka:
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm upgrade -i --atomic --timeout $(HELM_TIMEOUT) on-prem-kafka bitnami/kafka --version $(KAFKA_CHART_VERSION) -f <(envsubst < kafka.values.yaml)

uninstall-kafka:
	helm uninstall on-prem-kafka

install-postgres:
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm upgrade -i on-prem-postgres bitnami/postgresql -f postgres.values.yaml

uninstall-postgres:
	helm uninstall on-prem-postgres

install-sandbox-postgres: # bitnami/postgresql doesn't has jsquery
	kubectl apply -f sandbox-postgresql.yaml

uninstall-sandbox-postgres:
	kubectl delete -f sandbox-postgresql.yaml

create-datagateway-ingress:
	@INGRESS_NAME=datagateway
	SERVICE_NAME=datagateway
	SERVICE_PORT=80
	$(MAKE) create-ingress

create-registry-cert:
	@if ! [[ -f certs/registry.key ]] || ! [[ -f certs/registry.crt ]]; then
		mkdir -p certs
		openssl req \
			-newkey rsa:4096 -nodes -sha256 -keyout certs/registry.key \
			-subj "/CN=registry.$(CLUSTER_DOMAIN)" \
			-addext "subjectAltName = DNS:registry.$(CLUSTER_DOMAIN)" \
			-x509 -days 365 -out certs/registry.crt
	fi
	kubectl delete secret on-prem-registry || true
	kubectl create secret tls on-prem-registry --key certs/registry.key --cert certs/registry.crt

trust-registry-cert:
	@docker_cert=/etc/docker/certs.d/registry.$(CLUSTER_DOMAIN)/ca.crt
	if ! cmp certs/registry.crt $$docker_cert; then
		sudo mkdir -p $$(dirname $$docker_cert)
		sudo cp certs/registry.crt $$docker_cert
	fi

	ubuntu_cert=/usr/local/share/ca-certificates/registry.$(CLUSTER_DOMAIN).crt
	if ! cmp certs/registry.crt $$ubuntu_cert; then
		sudo cp certs/registry.crt $$ubuntu_cert
		sudo update-ca-certificates
	fi

download-artifacts:
	@config=$$(mktemp)
	envsubst < dgctl.config.yaml > $$config
	docker run --rm \
		-v $$config:/config.yaml \
		-v $$(pwd)/values:/values -v /var/run/docker.sock:/var/run/docker.sock \
		--network host \
		2gis/dgctl:latest pull --config=/config.yaml --version=$(ON_PREMISE_VERSION) --apps-to-registry --generate-values
	rm -f $$config
	export manifest=$$(grep -o '[^/]*.json' values/general.yaml)
	envsubst < dgctl.values.yaml >  values/dgctl.values.yaml

# -- Утилиты

INGRESS_NAME ?=
SERVICE_NAME ?=
SERVICE_PORT ?=
create-ingress:
	@CLUSTER_DOMAIN=$(CLUSTER_DOMAIN)
	kubectl apply -f <(envsubst < ingress.tpl.yaml)
