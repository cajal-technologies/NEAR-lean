.PHONY: build test lint audit format format-check scorecard nearcore-references \
	negative-tests differential-self-test differential-smoke receipt-smoke differential-campaign \
	receipt-campaign block-smoke block-campaign economic-smoke economic-campaign wasm-campaign \
	oracle-install wasm-artifacts wasm-validation wasm-smoke m10-validation m10-smoke \
	m10-campaign m11-validation validation-campaign \
	m12-validation m12-exact-gate m12-latest m12-latest-smoke \
	m13-validation m13-latest m13-latest-smoke \
	m14-validation m14-latest m14-latest-smoke \
	differential-nightly ci ci-online notes

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

wasm-artifacts: oracle-install
	node scripts/wasm_artifacts.mjs --check

wasm-validation: build
	python3 scripts/wasm_report.py --check

wasm-smoke: oracle-install
	python3 scripts/differential.py smoke differential/fixtures/wasm-counter.json --level L4

m10-validation: build
	lake build m10Validation --wfail
	python3 scripts/m10_report.py --check

m10-smoke: oracle-install
	python3 scripts/differential.py smoke differential/fixtures/wasm-benchmarks.json --level L5

m10-campaign: oracle-install
	python3 scripts/differential.py wasm-benchmark-campaign
	python3 scripts/m10_report.py

m11-validation: build
	lake build m11Validation --wfail
	python3 scripts/m11_corpus.py --check
	python3 scripts/m11_report.py --check

m12-validation: build
	lake build m12Validation --wfail
	python3 scripts/m12_fetch.py --check
	python3 scripts/m12_replay.py --check
	python3 scripts/m12_replay.py --self-test
	python3 scripts/m12_report.py --check
	python3 scripts/m12_witness_gate.py --check-contract --self-test
	Oracle/m12_exact_replay --self-test
	python3 scripts/m12_latest.py --self-test --check-report

m12-exact-gate: m12-validation
	python3 scripts/m12_witness_gate.py --exact

m12-latest:
	python3 scripts/m12_latest.py --count 100 --output replay/latest-report.json

m12-latest-smoke:
	python3 scripts/m12_latest.py --count 10 --live

m13-validation: build
	python3 scripts/m13_latest.py --self-test --check-report

m13-latest:
	python3 scripts/m13_latest.py --count 100 --output replay/latest-sharding-report.json

m13-latest-smoke:
	python3 scripts/m13_latest.py --count 10 --live

m14-validation:
	python3 scripts/m14_latest.py --self-test --check-report

m14-latest:
	python3 scripts/m14_latest.py --count 100 --output replay/latest-stabilization-report.json

m14-latest-smoke:
	python3 scripts/m14_latest.py --count 10 --live

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

wasm-campaign: oracle-install
	python3 scripts/differential.py wasm-campaign

validation-campaign:
	python3 scripts/validation.py --actions 1000000 --seed 1 --output validation/report.json

differential-nightly: oracle-install
	python3 scripts/differential.py receipt-campaign --count 5000 --seed 1 \
		--output validation/nightly-visible.json
	python3 scripts/differential.py receipt-campaign --count 5000 --seed 100001 \
		--output validation/nightly-held-out.json

notes:
	uv run python -m http.server

ci: format-check lint test scorecard nearcore-references negative-tests differential-self-test \
	wasm-artifacts wasm-validation m10-validation m11-validation m12-validation m13-validation \
	m14-validation
	python3 scripts/validation.py --actions 1000000 --seed 1 --output validation/report.json --check

ci-online: ci
	python3 scripts/check.py nearcore-references --online
	$(MAKE) differential-smoke
	$(MAKE) receipt-smoke
	$(MAKE) block-smoke
	$(MAKE) economic-smoke
	$(MAKE) wasm-smoke
	$(MAKE) m10-smoke
	$(MAKE) m12-latest-smoke
	$(MAKE) m13-latest-smoke
	$(MAKE) m14-latest-smoke
