.PHONY: build test lint audit format format-check scorecard nearcore-references \
	negative-tests differential-self-test differential-smoke differential-campaign \
	oracle-install ci ci-online notes

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

differential-campaign: oracle-install
	python3 scripts/differential.py campaign --count 1000 --seed 1

notes:
	uv run python -m http.server

ci: format-check lint test scorecard nearcore-references negative-tests differential-self-test

ci-online: ci
	python3 scripts/check.py nearcore-references --online
	$(MAKE) differential-smoke
