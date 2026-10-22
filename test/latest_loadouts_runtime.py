"""Check embedded patch profiles using only the copied executable and snapshots."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from runtime import clean_env


def verify(binary_path, fixture_path):
    fixture = Path(fixture_path).resolve()
    with tempfile.TemporaryDirectory(prefix='powerspike-loadouts-runtime-') as temporary:
        cwd = Path(temporary)
        binary = cwd / 'powerspike'
        shutil.copyfile(Path(binary_path).resolve(), binary)
        binary.chmod(0o755)
        shutil.copytree(fixture / 'seed', cwd / 'seed')
        env = clean_env(PS_DATA_DIR=str(cwd / 'data'), PS_SEED_DIR=str(cwd / 'seed'))
        cases = json.loads((fixture / 'cases.json').read_text())
        assert len(cases) >= 64
        for index, case in enumerate(cases):
            scenario = cwd / 'scenario.json'
            scenario.write_text(json.dumps(case['document']))
            outcome = json.loads(subprocess.check_output(
                [str(binary), '--simulate', str(scenario)], cwd=cwd, env=env, text=True, timeout=10))
            assert outcome['metrics'] == case['metrics'], index
            for actual, expected in zip(outcome['actors'], case['actors'], strict=True):
                for key, value in expected.items():
                    assert actual.get(key) == value, (index, key, actual.get(key), value)
    print(f'Relocated executable: {len(cases)} latest-patch loadouts, both roles, Kayle boundaries, fixed forms, rune shards and immutable cached snapshots passed.')


if __name__ == '__main__':
    verify(*sys.argv[1:])
