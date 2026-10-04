"""Check normalization boundaries where tooltip text can mislead the model."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from import_catalog import normalize_champion, normalize_item

ROOT = Path(__file__).resolve().parents[1] / 'data/16.19.1/catalog/sources'


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items = json.loads((ROOT / 'items-ddragon.json').read_text())['data']
        cls.champions = json.loads((ROOT / 'champions-ddragon.json').read_text())['data']

    def test_stat_blocks_do_not_turn_conditional_passives_into_permanent_stats(self):
        kraken = normalize_item('6672', self.items['6672'])
        self.assertEqual(kraken['stats']['ad'], 45)
        self.assertNotIn('on-hit', kraken['stats'])
        self.assertTrue(kraken['limitations'])
        cleaver = normalize_item('3071', self.items['3071'])
        self.assertEqual(cleaver['stats']['ability-haste'], 20)
        self.assertNotIn('armor-pen-percent', cleaver['stats'])
        mejai = normalize_item('3041', self.items['3041'])
        self.assertEqual(mejai['stats']['ap'], 20)
        self.assertNotIn('move-speed-percent', mejai['stats'])

    def test_percent_stats_and_flat_regeneration_have_explicit_units(self):
        dominik = normalize_item('3036', self.items['3036'])
        self.assertAlmostEqual(dominik['stats']['armor-pen-percent'], .35)
        shield = normalize_item('1054', self.items['1054'])
        self.assertEqual(shield['stats']['hp-regen'], 4)
        old_bead = normalize_item('771006', self.items['771006'])
        self.assertEqual(old_bead['stats']['hp-regen'], 5)

    def test_unmodeled_fields_remain_visible(self):
        blade = normalize_item('1055', self.items['1055'])
        self.assertTrue(any('Omnivamp' in line for line in blade['limitations']))

    def test_character_record_corrects_known_dragon_growth_error(self):
        garen = self.champions['Garen']
        source = json.loads((ROOT / 'characters/Garen.json').read_text())
        result = normalize_champion(garen, source)
        self.assertEqual(garen['stats']['attackdamageperlevel'], 0)
        self.assertEqual(result['growth']['ad'], 4.5)
        self.assertEqual(result['status'], 'unvalidated')

    def test_missing_record_fields_are_explicit_fallbacks(self):
        source = json.loads((ROOT / 'characters/Jhin.json').read_text())
        result = normalize_champion(self.champions['Jhin'], source)
        self.assertTrue(any('Data Dragon attackspeedperlevel' in line for line in result['limitations']))


if __name__ == '__main__':
    unittest.main()
