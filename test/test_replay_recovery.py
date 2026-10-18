"""Check that recovery validation cannot silently manufacture coverage."""
import copy
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import replay_recovery
from replay_recovery import champion_start, match_deaths, validate


class RecoveryTests(unittest.TestCase):
    def test_unseen_payload_abstains_without_learning_from_validation(self):
        roster = [{'SKIN': f'C{i}', 'TEAM': '100' if i < 5 else '200',
                     'CHAMPIONS_KILLED': '0', 'NUM_DEATHS': '0', 'ASSISTS': '0'} for i in range(10)]
        class Replay:
            header = SimpleNamespace(client_version='build', protocol_digest='protocol')
            metadata = SimpleNamespace(game_length=1000000, participants=roster)
            def __enter__(self): return self
            def __exit__(self, *args): pass
        profile = {'format': 'powerspike-replay-recovery-profile', 'version': 1,
                   'client-build': 'build', 'protocol-digest': 'protocol',
                   'events': {'skill-upgrade': {'opcode': 810, 'payload-codebook': {
                       '0102': {'skill-slot': 1, 'level-up-type': 'NORMAL'}}}}}
        original = copy.deepcopy(profile)
        blocks = [SimpleNamespace(param=0x400000ae + i, timestamp=t, packet_id=1)
                  for i in range(10) for t in (0, 1000)]
        blocks.append(SimpleNamespace(param=0x400000ae, timestamp=500, packet_id=810,
                                      stream='gameChunk', chunk_id=1, block_offset=42,
                                      payload=b'\xde\xad'))
        module = SimpleNamespace(ReplayReader=SimpleNamespace(open=lambda path: Replay()))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'synthetic.rofl'; path.write_bytes(b'synthetic fixture')
            with patch.dict(sys.modules, {'rofllens': module}), \
                    patch.object(replay_recovery, 'iter_blocks', return_value=iter(blocks)), \
                    patch.object(replay_recovery.importlib.metadata, 'version', return_value='0.1.0'):
                result, _ = replay_recovery.recover(path, profile)
            self.assertEqual(result['events'][0]['decode-status'], 'unknown-payload')
            self.assertNotIn('skill-slot', result['events'][0])
            self.assertEqual(profile, original)
            profile['client-build'] = 'another-build'
            with patch.dict(sys.modules, {'rofllens': module}), self.assertRaises(ValueError):
                replay_recovery.recover(path, profile)

    def test_duplicate_or_missing_deaths_cannot_pass(self):
        observed = [{'event-id': 'one', 'timestamp': 1., 'victimId': 1}]
        truth = [{'timestamp': 1000, 'victimId': 1}]
        self.assertTrue(match_deaths(observed, truth, .01)['passed'])
        self.assertFalse(match_deaths(observed * 2, truth, .01)['passed'])
        self.assertFalse(match_deaths([], truth, .01)['passed'])
        self.assertFalse(match_deaths([], [], .01)['passed'])

    def test_victim_and_timing_must_both_match(self):
        truth = [{'timestamp': 1000, 'victimId': 1}]
        for t, victim in [(1., 2), (1.02, 1)]:
            got = match_deaths([{'event-id': 'one', 'timestamp': t, 'victimId': victim}], truth, .01)
            self.assertEqual((got['matched'], got['unexpected'], got['missing']), (0, 1, 1))

    def test_ambiguous_timeline_events_are_not_merged(self):
        event = {'event-id': 'one', 'timestamp': 1., 'victimId': 1}
        truth = [{'timestamp': 1000, 'victimId': 1}, {'timestamp': 1001, 'victimId': 1}]
        result = match_deaths([event], truth, .01)
        self.assertEqual(result['ambiguous'], 1)
        self.assertFalse(result['passed'])

    def test_ambiguous_or_short_lived_entity_runs_are_rejected(self):
        entities = {i: {'first': 0, 'last': 1000, 'opcodes': {1}} for i in range(12)}
        with self.assertRaises(ValueError):
            champion_start(entities, 10, 1000)
        entities = {i: {'first': 100, 'last': 1000, 'opcodes': {1}} for i in range(10)}
        with self.assertRaises(ValueError):
            champion_start(entities, 10, 1000)

    def test_wrong_game_identity_build_or_roster_is_rejected(self):
        participants = [{'championName': f'C{i}', 'teamId': 100 if i < 5 else 200,
                         'participantId': i + 1, 'kills': 0, 'deaths': 0,
                         'assists': 0, 'puuid': f'p{i}'} for i in range(10)]
        stats = {(p['championName'], p['teamId']): (0, 0, 0) for p in participants}
        report = {'client-build': '16.20.824.8524', 'duration-seconds': 1000,
                  'roster': [{'slot': i, 'champion': p['championName'], 'team': p['teamId']}
                             for i, p in enumerate(participants)], 'events': []}
        match = {'metadata': {'matchId': 'one'}, 'info': {'gameVersion': report['client-build'],
                 'gameDuration': 1000, 'participants': participants}}
        timeline = {'metadata': {'matchId': 'one', 'participants': [p['puuid'] for p in participants]},
                    'info': {'frames': []}}
        variants = []
        changed = copy.deepcopy(match); changed['metadata']['matchId'] = 'two'; variants.append((changed, timeline))
        changed = copy.deepcopy(match); changed['info']['gameVersion'] = '16.19'; variants.append((changed, timeline))
        changed = copy.deepcopy(match); changed['info']['participants'][0]['deaths'] = 1; variants.append((changed, timeline))
        changed = copy.deepcopy(timeline); changed['metadata']['participants'][0] = 'wrong'; variants.append((match, changed))
        for m, t in variants:
            with self.assertRaises(ValueError):
                validate(report, stats, m, t, .01)


if __name__ == '__main__':
    unittest.main()
