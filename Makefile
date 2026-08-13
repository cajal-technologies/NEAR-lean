.PHONY: build test lint audit format format-check scorecard nearcore-references \
	negative-tests differential-self-test differential-smoke receipt-smoke differential-campaign \
	receipt-campaign block-smoke block-campaign economic-smoke economic-campaign \
	oracle-install validation-campaign differential-nightly ci ci-online notes

build:
	lake build --wfail

test:
	lake test --wfail

lint: build
	python3 scripts/check.py lint

audit: build
	python3 scripts/check.py audit --check

format: format-check

format-check:
	python3 scripts/check.py format

scorecard:
	python3 scripts/check.py scorecard --output scorecard.json --check

nearcore-references:
	python3 scripts/check.py nearcore-references

negative-tests:
	python3 scripts/check.py negative-tests

differential-self-test:
	python3 scripts/differential.py self-test

oracle-install:
	npm ci --prefix Oracle --ignore-scripts

differential-smoke: oracle-install
	python3 scripts/differential.py smoke

receipt-smoke: oracle-install
	python3 scripts/differential.py smoke differential/fixtures/async.json --level L4

block-smoke: oracle-install
	python3 scripts/differential.py smoke differential/fixtures/block.json --level L4

economic-smoke: oracle-install
	python3 scripts/differential.py smoke differential/fixtures/economic.json --level L5

differential-campaign: oracle-install
	python3 scripts/differential.py campaign --count 1000 --seed 1

receipt-campaign: oracle-install
	python3 scripts/differential.py receipt-campaign --count 10000 --seed 1

block-campaign: oracle-install
	python3 scripts/differential.py block-campaign --count 10000 --seed 1

economic-campaign: oracle-install
	python3 scripts/differential.py economic-campaign --count 10000 --seed 1

validation-campaign:
	python3 scripts/validation.py --actions 1000000 --seed 1 --output validation/report.json

differential-nightly: oracle-install
	python3 scripts/differential.py receipt-campaign --count 5000 --seed 1 \
		--output validation/nightly-visible.json
	python3 scripts/differential.py receipt-campaign --count 5000 --seed 100001 \
		--output validation/nightly-held-out.json

notes:
	uv run python -m http.server

ci: format-check lint test scorecard nearcore-references negative-tests differential-self-test
	python3 scripts/validation.py --actions 1000000 --seed 1 --output validation/report.json --check

ci-online: ci
	python3 scripts/check.py nearcore-references --online
	$(MAKE) differential-smoke
	$(MAKE) receipt-smoke
	$(MAKE) block-smoke
	$(MAKE) economic-smoke
