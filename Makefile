.PHONY: build test lint audit format format-check scorecard nearcore-references \
	negative-tests ci ci-online notes

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

notes:
	uv run python -m http.server

ci: format-check lint test scorecard nearcore-references negative-tests

ci-online: ci
	python3 scripts/check.py nearcore-references --online
