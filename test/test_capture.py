"""Synthetic API responses exercise transport and normalization; these are not game observations."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import capture_live_stats as capture
from jdn import dumps
import verify_sources


def response():
    return {
        'activePlayer': {'riotId': 'Example#EUW', 'summonerName': 'Legacy', 'level': 1,
            'abilities': {slot: {'abilityLevel': 1 if slot == 'Q' else 0} for slot in 'QWER'},
            'championStats': {'attackDamage': 50, 'abilityPower': 0, 'maxHealth': 560,
                'armor': 23, 'magicResist': 30, 'attackSpeed': .61, 'moveSpeed': 335,
                'abilityHaste': 0, 'critChance': 25, 'critDamage': 200,
                'magicPenetrationPercent': .6, 'armorPenetrationPercent': 1},
            'fullRunes': {'generalRunes': [{'id': 8234}], 'statRunes': [{'id': 5008}]}},
        'allPlayers': [{'riotId': 'Example#EUW', 'summonerName': 'Legacy', 'level': 1,
            'rawChampionName': 'game_character_displayname_Annie', 'isDead': False, 'items': []}],
        'gameData': {'gameTime': 15, 'mapNumber': 11, 'gameMode': 'CLASSIC'},
    }


class CaptureTests(unittest.TestCase):
    def normalize(self, data=None, units=None):
        return capture.normalize(data or response(), '16.19.1', 'test-build', units or {}, 'synthetic-test')

    def test_units_are_explicit_and_missing_units_remain_unmapped(self):
        record = self.normalize()
        self.assertNotIn('crit-chance', record['observed'])
        self.assertEqual(len(record['unmapped-fields']), 4)
        self.assertFalse(record['context-reviewed'])
        self.assertEqual(record['rune-ids'], [8234])
        self.assertEqual(record['shard-ids'], [5008])
        mapped = self.normalize(units={'critChance': 'percent', 'critDamage': 'percent',
                                      'magicPenetrationPercent': 'remaining-fraction'})
        self.assertEqual(mapped['observed']['crit-chance'], .25)
        self.assertEqual(mapped['observed']['crit-damage'], 2)
        self.assertAlmostEqual(mapped['observed']['magic-pen-percent'], .4)

    def test_missing_haste_is_not_inferred_from_stale_cdr_field(self):
        data = response()
        del data['activePlayer']['championStats']['abilityHaste']
        data['activePlayer']['championStats']['cooldownReduction'] = .1
        self.assertNotIn('ability-haste', self.normalize(data)['observed'])

    def test_identity_supports_new_and_legacy_fields(self):
        data = response()
        del data['activePlayer']['riotId']
        self.assertEqual(self.normalize(data)['champion'], 'Annie')
        data['allPlayers'].append(copy.deepcopy(data['allPlayers'][0]))
        with self.assertRaises(ValueError):
            self.normalize(data)

    def test_inventory_retains_unknown_items_but_separates_trinket_slot(self):
        data = response()
        data['allPlayers'][0]['items'] = [{'itemID': 1052, 'count': 2, 'slot': 0},
            {'itemID': 9999, 'count': 1, 'slot': 1}, {'itemID': 3340, 'count': 1, 'slot': 6}]
        record = self.normalize(data)
        self.assertEqual(record['item-ids'], ['1052', '1052', '9999'])
        self.assertEqual(record['ignored-trinket-ids'], ['3340'])

    def test_bad_numbers_and_wrong_unit_choices_are_rejected(self):
        for value in [True, float('nan'), float('inf')]:
            data = response()
            data['activePlayer']['championStats']['attackDamage'] = value
            with self.assertRaises(ValueError):
                self.normalize(data)
        with self.assertRaises(ValueError):
            self.normalize(units={'critChance': 'fraction'})
        with self.assertRaises(ValueError):
            self.normalize(units={'critChance': 'guess'})

    def test_inconsistent_response_is_rejected(self):
        data = response()
        data['allPlayers'][0]['level'] = 2
        with self.assertRaises(ValueError):
            self.normalize(data)

    def test_import_preserves_raw_response_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            source, output = path / 'input.json', path / 'capture'
            raw = json.dumps(response()).encode('utf-8')
            source.write_bytes(raw)
            argv = ['--input', str(source), '--output', str(output), '--patch', '16.19.1',
                    '--client-build', 'synthetic-test']
            capture.main(argv)
            self.assertEqual((output / 'raw.json').read_bytes(), raw)
            self.assertIn(hashlib.sha256(raw).hexdigest(), (output / 'observation.jdn').read_text())
            with self.assertRaises(FileExistsError):
                capture.main(argv)
            self.assertEqual((output / 'raw.json').read_bytes(), raw)

    def test_live_branch_requests_only_the_fixed_local_endpoint(self):
        with tempfile.TemporaryDirectory() as temp:
            response_mock = MagicMock()
            response_mock.__enter__.return_value.read.return_value = json.dumps(response()).encode('utf-8')
            output = Path(temp) / 'capture'
            with patch('urllib.request.OpenerDirector.open', return_value=response_mock) as request:
                capture.main(['--output', str(output), '--patch', '16.19.1',
                              '--client-build', 'synthetic-test', '--insecure-localhost'])
            request.assert_called_once_with('https://127.0.0.1:2999/liveclientdata/allgamedata', timeout=5)
            self.assertIn(':source "live-client-api"', (output / 'observation.jdn').read_text())

    def test_jdn_round_trip_and_comparison_cli(self):
        janet = ROOT / 'build/janet'
        if not janet.exists():
            self.skipTest('built-in Janet runtime unavailable')
        record = self.normalize()
        # This synthetic baseline represents no stat shards; other fixtures test their application.
        record['shard-ids'] = []
        record['context-reviewed'] = True
        record['buffs'] = []
        record['role-quest-state'] = 'inactive'
        record['notes'] = 'Synthetic \"test\" with Unicode é, newline\n and NUL\x00; never game evidence.'
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'observation.jdn'
            path.write_text(dumps(record), encoding='utf-8')
            result = subprocess.run([str(janet), 'scripts/compare_stats.janet', str(path)],
                                    cwd=ROOT, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('8 checked, 0 mismatches, 0 missing', result.stdout)
            record['observed']['ap'] = 18
            path.write_text(dumps(record), encoding='utf-8')
            mismatch = subprocess.run([str(janet), 'scripts/compare_stats.janet', str(path)],
                                      cwd=ROOT, text=True, capture_output=True)
            self.assertEqual(mismatch.returncode, 1)
            self.assertIn('1 mismatches', mismatch.stdout)


class SourceTests(unittest.TestCase):
    def test_hash_verification_catches_modified_retained_data(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            (path / 'source.json').write_text('{}')
            (path / 'manifest.json').write_text(json.dumps({'retained_excerpts': [
                {'path': 'source.json', 'sha256': 'incorrect'}]}))
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                verify_sources.facts(path)

    def test_legacy_spell_selection_is_rejected_even_with_matching_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            data_root = Path(temp) / 'data'
            shutil.copytree(ROOT / 'data/16.19.1', data_root)
            path = data_root / 'sources/annie-q-w-spells.json'
            spells = json.loads(path.read_text())
            current = next(iter(spells))
            spells['Characters/Annie/Spells/Disintegrate'] = spells.pop(current)
            path.write_text(json.dumps(spells))
            manifest_path = data_root / 'manifest.json'
            manifest = json.loads(manifest_path.read_text())
            for entry in manifest['retained_excerpts']:
                if entry['path'] == 'sources/annie-q-w-spells.json':
                    entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'current champion references'):
                verify_sources.facts(data_root)


if __name__ == '__main__':
    unittest.main()
