.PHONY: build test lint format scorecard negative-tests ci

build:
	lake build --wfail

test:
	lake test --wfail

lint: build
	python3 scripts/check.py lint

format:
	python3 scripts/check.py format

scorecard:
	python3 scripts/check.py scorecard --output scorecard.json --check

negative-tests:
	python3 scripts/check.py negative-tests

ci: format lint test scorecard negative-tests
