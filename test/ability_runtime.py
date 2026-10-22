"""Reviewed ability mechanics must survive relocation without source files."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from runtime import clean_env


def verify(binary_path, fixture_path):
    fixture = Path(fixture_path).resolve()
    with tempfile.TemporaryDirectory(prefix='powerspike-ability-runtime-') as temporary:
        cwd = Path(temporary)
        binary = cwd / 'powerspike'
        shutil.copyfile(Path(binary_path).resolve(), binary)
        binary.chmod(0o755)
        shutil.copytree(fixture / 'seed', cwd / 'seed')
        env = clean_env(PS_DATA_DIR=str(cwd / 'data'), PS_SEED_DIR=str(cwd / 'seed'))
        cases = json.loads((fixture / 'cases.json').read_text())
        assert cases
        for case in cases:
            scenario = cwd / 'scenario.json'
            scenario.write_text(json.dumps(case['document']))
            outcome = json.loads(subprocess.check_output(
                [str(binary), '--simulate', str(scenario)], cwd=cwd, env=env, text=True, timeout=10))
            assert outcome['metrics'] == case['metrics']
            for source in case['sources']:
                assert any(event['kind'] == 'damage' and event.get('source') == source
                           for event in outcome['trace'])
    print(f'Relocated executable: {len(cases)} reviewed ability scenarios and scoring parity passed.')


if __name__ == '__main__':
    verify(*sys.argv[1:])
