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
	JANET_PATH=build/web-modules $(JANET) test/champion-configs.janet
	JANET_PATH=build/web-modules $(JANET) test/patch-upgrades.janet
	JANET_PATH=build/web-modules $(JANET) test/pickers.janet
	JANET_PATH=build/web-modules $(JANET) test/select-options.janet
	JANET_PATH=build/web-modules $(JANET) test/packages.janet
	JANET_PATH=build/web-modules $(JANET) test/patch-deadline.janet
	JANET_PATH=build/web-modules $(JANET) test/storage.janet
	JANET_PATH=build/web-modules $(JANET) test/storage-packages.janet
	JANET_PATH=build/web-modules $(JANET) test/assets.janet
	JANET_PATH=build/web-modules $(JANET) test/job-queue.janet
	$(PYTHON) test/https.py --janet $(JANET)
	JANET_PATH=build/web-modules $(JANET) test/parser.janet
	JANET_PATH=build/web-modules $(JANET) test/latest-patch.janet
	JANET_PATH=build/web-modules $(JANET) test/latest-mages.janet
	JANET_PATH=build/web-modules $(JANET) test/latest-attacks.janet
	JANET_PATH=build/web-modules $(JANET) test/latest-loadouts.janet
	JANET_PATH=build/web-modules $(JANET) test/ability-audit.janet
	JANET_PATH=build/web-modules $(JANET) test/garen-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/seraphine-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/fiddlesticks-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/defense-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/vayne-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/completeness-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/twenty-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/twenty-five-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-defense-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/areas-impact-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/sustain-charge-abilities.janet
	JANET_PATH=build/web-modules $(JANET) test/reparse.janet
	JANET_PATH=build/web-modules $(JANET) test/level-scaling.janet
	JANET_PATH=build/web-modules $(JANET) test/engine.janet
	JANET_PATH=build/web-modules PS_STATUS_FIXTURE=$(CURDIR)/build/status-timeline-browser.json $(JANET) test/status-timeline.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-cadence.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-limits.janet
	JANET_PATH=build/web-modules $(JANET) test/ability-readiness.janet
	JANET_PATH=build/web-modules $(JANET) test/control-resumption.janet
	JANET_PATH=build/web-modules $(JANET) test/attack-resets.janet
	JANET_PATH=build/web-modules $(JANET) test/resource-readiness.janet
	JANET_PATH=build/web-modules $(JANET) test/health-activation.janet
	JANET_PATH=build/web-modules $(JANET) test/movement-readiness.janet
	JANET_PATH=build/web-modules $(JANET) test/changing-readiness.janet
	JANET_PATH=build/web-modules $(JANET) test/health-cost-readiness.janet
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
	JANET_PATH=build/web-modules PS_GAREN_FIXTURE=$(CURDIR)/build/garen-runtime-fixture $(JANET) test/garen-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/garen-runtime-fixture
	JANET_PATH=build/web-modules PS_SERAPHINE_FIXTURE=$(CURDIR)/build/seraphine-runtime-fixture $(JANET) test/seraphine-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/seraphine-runtime-fixture
	JANET_PATH=build/web-modules PS_FIDDLESTICKS_FIXTURE=$(CURDIR)/build/fiddlesticks-runtime-fixture $(JANET) test/fiddlesticks-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/fiddlesticks-runtime-fixture
	JANET_PATH=build/web-modules PS_DEFENSE_ABILITY_FIXTURE=$(CURDIR)/build/defense-ability-runtime-fixture $(JANET) test/defense-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/defense-ability-runtime-fixture
	JANET_PATH=build/web-modules PS_VAYNE_FIXTURE=$(CURDIR)/build/vayne-runtime-fixture $(JANET) test/vayne-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/vayne-runtime-fixture
	JANET_PATH=build/web-modules PS_COMPLETENESS_FIXTURE=$(CURDIR)/build/completeness-runtime-fixture $(JANET) test/completeness-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/completeness-runtime-fixture
	JANET_PATH=build/web-modules PS_TWENTY_FIXTURE=$(CURDIR)/build/twenty-runtime-fixture $(JANET) test/twenty-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/twenty-runtime-fixture
	JANET_PATH=build/web-modules PS_TWENTY_FIVE_FIXTURE=$(CURDIR)/build/twenty-five-runtime-fixture $(JANET) test/twenty-five-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/twenty-five-runtime-fixture
	JANET_PATH=build/web-modules PS_ATTACK_DEFENSE_FIXTURE=$(CURDIR)/build/attack-defense-runtime-fixture $(JANET) test/attack-defense-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/attack-defense-runtime-fixture
	JANET_PATH=build/web-modules PS_AREAS_IMPACT_FIXTURE=$(CURDIR)/build/areas-impact-runtime-fixture $(JANET) test/areas-impact-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/areas-impact-runtime-fixture
	JANET_PATH=build/web-modules PS_SUSTAIN_CHARGE_FIXTURE=$(CURDIR)/build/sustain-charge-runtime-fixture $(JANET) test/sustain-charge-abilities.janet
	$(PYTHON) test/ability_runtime.py dist/bin/powerspike build/sustain-charge-runtime-fixture
	JANET_PATH=build/web-modules PS_LATEST_LOADOUT_FIXTURE=$(CURDIR)/build/latest-loadout-runtime-fixture $(JANET) test/latest-loadouts.janet
	$(PYTHON) test/latest_loadouts_runtime.py dist/bin/powerspike build/latest-loadout-runtime-fixture
	JANET_PATH=build/web-modules PS_REPARSE_FIXTURE=$(CURDIR)/build/reparse-runtime-fixture $(JANET) test/reparse.janet
	JANET_PATH=build/web-modules PS_LATEST_PATCH_FIXTURE=$(CURDIR)/build/latest-patch-runtime-fixture $(JANET) test/latest-patch.janet
	JANET_PATH=build/web-modules PS_LATEST_ATTACK_FIXTURE=$(CURDIR)/build/latest-attack-runtime-fixture $(JANET) test/latest-attacks.janet
	JANET_PATH=build/web-modules PS_PARRY_FIXTURE=$(CURDIR)/build/parry-runtime-fixture $(JANET) test/parry.janet
	JANET_PATH=build/web-modules PS_LEVEL_SCALING_FIXTURE=$(CURDIR)/build/level-scaling-runtime-fixture $(JANET) test/level-scaling.janet
	JANET_PATH=build/web-modules PS_CONTROL_FIXTURE=$(CURDIR)/build/control-runtime-fixture $(JANET) test/control-resumption.janet
	JANET_PATH=build/web-modules PS_RESET_FIXTURE=$(CURDIR)/build/reset-runtime-fixture $(JANET) test/attack-resets.janet
	JANET_PATH=build/web-modules PS_RESOURCE_FIXTURE=$(CURDIR)/build/resource-runtime-fixture $(JANET) test/resource-readiness.janet
	JANET_PATH=build/web-modules PS_HEALTH_FIXTURE=$(CURDIR)/build/health-runtime-fixture $(JANET) test/health-activation.janet
	JANET_PATH=build/web-modules PS_MOVEMENT_FIXTURE=$(CURDIR)/build/movement-runtime-fixture $(JANET) test/movement-readiness.janet
	JANET_PATH=build/web-modules PS_CHANGING_FIXTURE=$(CURDIR)/build/changing-runtime-fixture $(JANET) test/changing-readiness.janet
	JANET_PATH=build/web-modules PS_HEALTH_COST_FIXTURE=$(CURDIR)/build/health-cost-runtime-fixture $(JANET) test/health-cost-readiness.janet
	$(PYTHON) test/runtime.py dist/bin/powerspike --parry-fixture build/parry-runtime-fixture --level-scaling-fixture build/level-scaling-runtime-fixture --control-fixture build/control-runtime-fixture --reset-fixture build/reset-runtime-fixture --resource-fixture build/resource-runtime-fixture --health-fixture build/health-runtime-fixture --movement-fixture build/movement-runtime-fixture --changing-fixture build/changing-runtime-fixture --health-cost-fixture build/health-cost-runtime-fixture --latest-attack-fixture build/latest-attack-runtime-fixture
	$(PYTHON) test/concurrency.py dist/bin/powerspike

test-package:
	$(PYTHON) test/package.py $(RPM)
