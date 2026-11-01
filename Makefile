.PHONY: check fmt lint validate test
fmt:
	terraform fmt -check -recursive
lint:
	tflint --recursive --format compact
validate:
	terraform -chdir=apps/onboard/aws init -backend=false -input=false -lockfile=readonly
	terraform -chdir=apps/onboard/aws validate
	terraform -chdir=apps/onboard/gcp init -backend=false -input=false -lockfile=readonly
	terraform -chdir=apps/onboard/gcp validate
	terraform -chdir=apps/onboard/aws/state-bootstrap init -backend=false -input=false -lockfile=readonly
	terraform -chdir=apps/onboard/aws/state-bootstrap validate
check: fmt lint validate
test: validate
	terraform -chdir=apps/onboard/aws test
	terraform -chdir=apps/onboard/gcp test
