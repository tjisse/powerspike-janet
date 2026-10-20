JANET ?= build/janet
PYTHON ?= python3

.PHONY: test verify-sources demo optimize rotation optimize-abilities optimize-total web-setup serve test-web build rpm format format-check test-format test-runtime test-package
.PHONY: verification-report

build/janet: scripts/bootstrap-janet.sh
	sh scripts/bootstrap-janet.sh

verification-report:
	$(PYTHON) scripts/replay_coverage.py report --output observations/verification/progress.json

# Replay comparisons exercise the production engine and its native modules.
# Prepare them before Python discovery, including on a clean release runner.
test: $(JANET) build/web-ready format-check
	JANET=$(JANET) bash test/format.sh
	$(JANET) test/run.janet
	$(PYTHON) scripts/verify_sources.py --janet $(JANET)
	$(PYTHON) scripts/import_catalog.py --check
	$(PYTHON) -m unittest discover -s test -p 'test_*.py'

verify-sources: $(JANET)
	$(PYTHON) scripts/verify_sources.py --janet $(JANET)

demo: $(JANET)
	$(JANET) main.janet demo

optimize: $(JANET)
	$(JANET) main.janet optimize

rotation: $(JANET)
	$(JANET) main.janet rotation

optimize-abilities: $(JANET)
	$(JANET) main.janet optimize-abilities

optimize-total: $(JANET)
	$(JANET) main.janet optimize-total

build/web-ready: build/janet scripts/bootstrap-web.sh scripts/fetch_web_assets.py scripts/seed-data.janet native/hash.c web/deps.lock docs/design/art-assets.json data/16.19.1/catalog/art-manifest.json data/16.19.1/catalog/catalog.jdn
	PYTHON=$(PYTHON) sh scripts/bootstrap-web.sh

web-setup: build/web-ready

serve: build/web-ready
	PS_DATA_DIR=$(CURDIR)/build/runtime-data PS_SEED_DIR=$(CURDIR)/build/seed $(JANET) web/main.janet

test-web: build/web-ready format-check
	JANET_PATH=build/web-modules $(JANET) test/web.janet
	JANET_PATH=build/web-modules $(JANET) test/matchup.janet
	JANET_PATH=build/web-modules $(JANET) test/patch-upgrades.janet
	JANET_PATH=build/web-modules $(JANET) test/packages.janet
	JANET_PATH=build/web-modules $(JANET) test/parser.janet
	JANET_PATH=build/web-modules $(JANET) test/level-scaling.janet
	JANET_PATH=build/web-modules $(JANET) test/engine.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-cadence.janet
	JANET_PATH=build/web-modules $(JANET) test/empowered-attacks.janet
	JANET_PATH=build/web-modules $(JANET) test/effects.janet
	JANET_PATH=build/web-modules $(JANET) test/runes.janet
	JANET_PATH=build/web-modules $(JANET) test/item-upgrades.janet
	JANET_PATH=build/web-modules $(JANET) test/lich-bane.janet
	JANET_PATH=build/web-modules $(JANET) test/parry.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-projectiles.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-styles.janet
	JANET_PATH=build/web-modules $(JANET) test/forms.janet
	JANET_PATH=build/web-modules $(JANET) test/mage-burst.janet
	JANET_PATH=build/web-modules $(JANET) test/objectives.janet
	JANET_PATH=build/web-modules $(JANET) test/search.janet
	JANET_PATH=build/web-modules $(JANET) test/fitness-cache.janet
	JANET_PATH=build/web-modules $(JANET) test/scenarios.janet
	$(JANET) test/config.janet

build: build/web-ready
	PYTHON=$(PYTHON) bash scripts/build.sh

rpm: test test-web test-runtime
	PYTHON=$(PYTHON) bash scripts/rpm.sh

build/formatter-ready: build/janet scripts/bootstrap-formatter.sh web/deps.lock
	bash scripts/bootstrap-formatter.sh

format: build/formatter-ready
	JANET=$(JANET) bash scripts/format.sh --write

format-check: build/formatter-ready
	JANET=$(JANET) bash scripts/format.sh --check

test-runtime: build
	JANET_PATH=build/web-modules PS_PARRY_FIXTURE=$(CURDIR)/build/parry-runtime-fixture $(JANET) test/parry.janet
	JANET_PATH=build/web-modules PS_LEVEL_SCALING_FIXTURE=$(CURDIR)/build/level-scaling-runtime-fixture $(JANET) test/level-scaling.janet
	$(PYTHON) test/runtime.py dist/bin/powerspike --parry-fixture build/parry-runtime-fixture --level-scaling-fixture build/level-scaling-runtime-fixture

test-package:
	$(PYTHON) test/package.py $(RPM)
