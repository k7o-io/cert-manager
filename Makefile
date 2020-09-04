.PHONY: lint install test uninstall

VERSION   ?= v1.0.1
K8Z       ?= dev
NAMESPACE ?= cert-manager
SHELL     := bash --noprofile --norc -O nullglob -euo pipefail

lint: policy/ base/resources/cert-manager-$(VERSION).yaml
	kubectl kustomize $(K8Z) | conftest test --combine -

install: base/resources/cert-manager-crds-$(VERSION).yaml lint
	kubectl apply --validate=false -f $<
	kubectl create ns $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f-
	kubectl wait --for condition=established --timeout=90s crd -l app.kubernetes.io/name=cert-manager
	kubectl apply -k $(K8Z)
	kubectl wait -n $(NAMESPACE) --for condition=available --timeout=5m deploy -l app.kubernetes.io/name=cert-manager

test:
	kubectl create ns test-self-signed
	kubectl apply -k tests/self-signed
	timeout 30s /bin/bash -c 'while true; do kubectl get -n test-self-signed secret/self-signed 2>/dev/null >/dev/null && break; done'
	@echo test-self-signed success
	kubectl delete ns test-self-signed

uninstall: base/resources/cert-manager-crds-$(VERSION).yaml
	kubectl delete -k $(K8Z)
	kubectl delete --ignore-not-found ns $(NAMESPACE)
	kubectl delete --ignore-not-found -f $<

base/resources/cert-manager-full-$(VERSION).yaml:
	curl -Lo $@ https://github.com/jetstack/cert-manager/releases/download/$(VERSION)/cert-manager.yaml

base/resources/cert-manager-$(VERSION).yaml: base/resources/cert-manager-full-$(VERSION).yaml
	kustomize cfg grep --annotate=false --invert-match kind=CustomResourceDefinition $< > $@
	ln -fsv $(notdir $@) base/resources/cert-manager.yaml

base/resources/cert-manager-crds-$(VERSION).yaml: base/resources/cert-manager-full-$(VERSION).yaml
	kustomize cfg grep --annotate=false kind=CustomResourceDefinition $< > $@

policy/:
	conftest pull https://github.com/ctison/conftest/releases/download/v0.0.1/kubernetes.tar.gz