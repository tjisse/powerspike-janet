"""Garen mechanics must survive relocation without source files or downloads."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from runtime import clean_env


def verify(binary_path, fixture_path):
    fixture = Path(fixture_path).resolve()
    with tempfile.TemporaryDirectory(prefix='powerspike-garen-runtime-') as temporary:
        cwd = Path(temporary)
        binary = cwd / 'powerspike'
        shutil.copyfile(Path(binary_path).resolve(), binary)
        binary.chmod(0o755)
        shutil.copytree(fixture / 'seed', cwd / 'seed')
        env = clean_env(PS_DATA_DIR=str(cwd / 'data'), PS_SEED_DIR=str(cwd / 'seed'))
        cases = json.loads((fixture / 'cases.json').read_text())
        assert len(cases) == 4
        for case in cases:
            scenario = cwd / 'scenario.json'
            scenario.write_text(json.dumps(case['document']))
            outcome = json.loads(subprocess.check_output(
                [str(binary), '--simulate', str(scenario)], cwd=cwd, env=env, text=True, timeout=10))
            assert outcome['metrics'] == case['metrics']
            garen = next(actor for actor in outcome['actors'] if actor.get('champion') == 'Garen')
            assert garen['stats']['attack-speed-item-growth'] > .6
            for source in ('GarenE', 'GarenR'):
                assert any(event['kind'] == 'damage' and event.get('source') == source
                           for event in outcome['trace'])
    print('Relocated executable: Garen E/R, both latest patches, both roles and scoring parity passed.')


if __name__ == '__main__':
    verify(*sys.argv[1:])
