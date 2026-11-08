import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).parents[1]/'usage_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class UsageTests(unittest.TestCase):
    def test_codex_multi_bucket_and_null_window(self):
        result = bridge.codex_windows({'rateLimitsByLimitId': {
            'codex': {'primary': {'usedPercent': 25, 'windowDurationMins': 300, 'resetsAt': 1800000000}, 'secondary': None},
            'other': {'primary': {'usedPercent': 100}}}})
        self.assertEqual([75, 0], [x['remainingPercent'] for x in result])
        self.assertEqual(['codex:primary', 'other:primary'], [x['id'] for x in result])
        self.assertTrue(result[0]['resetsAt'].endswith('+00:00'))

    def test_codex_legacy_and_missing(self):
        self.assertEqual([], bridge.codex_windows({}))
        self.assertEqual(60, bridge.codex_windows({'rateLimits': {'primary': {'usedPercent': 40}}})[0]['remainingPercent'])

    def test_invalid_percentages(self):
        for value in [True, None, '25', -1, 101, float('nan'), float('inf')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                bridge.percentage(value)

    def test_kimi_windows_are_independent(self):
        result = bridge.kimi_windows({'code': 0, 'data': {'kind': 'ok', 'quota': {'usages': {
            'limit5h': {'usedRatio': .2}, 'monthCode': {'usedRatio': 1}, 'future': {'usedRatio': .5}}}}})
        self.assertEqual([80, 0, 50], [x['remainingPercent'] for x in result])

    def test_kimi_in_band_errors(self):
        for value in [{'code': 40101}, {'code': 0, 'data': {'kind': 'error', 'message': 'private'}}]:
            with self.assertRaises(ValueError):
                bridge.kimi_windows(value)

    def test_kimi_rejects_remote_or_credential_urls_before_reading_token(self):
        for url in ['https://example.com', 'http://example.com', 'http://user:pass@localhost', 'http://localhost/?token=secret']:
            with self.assertRaises(ValueError):
                bridge.read_kimi(url, '/no/token/file')

    def test_provider_failure_is_redacted(self):
        def fail():
            raise ValueError('secret-credential')
        result = bridge.snapshot('Codex', fail)
        self.assertNotIn('secret-credential', json.dumps(result))
        self.assertEqual('unavailable', result['state'])

    def test_atomic_snapshot_is_private_and_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'usage'
            bridge.write_snapshot(path, {'schemaVersion': 1})
            bridge.write_snapshot(path, {'schemaVersion': 2})
            self.assertEqual(2, json.loads((path/'usage.json').read_text())['schemaVersion'])
            self.assertEqual(0o600, (path/'usage.json').stat().st_mode & 0o777)
            self.assertEqual(['usage.json'], [p.name for p in path.iterdir()])

    def test_codex_process_only_sends_account_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory)/'codex'
            fake.write_text('''#!/usr/bin/env python3
import sys,json
for line in sys.stdin:
 m=json.loads(line)
 if m['method']=='initialized': continue
 if m['method']=='initialize': result={}
 elif m['method']=='account/rateLimits/read': result={'rateLimits':{'primary':{'usedPercent':30}}}
 else: raise RuntimeError('Unexpected method')
 print(json.dumps({'id':m['id'],'result':result}),flush=True)
''')
            fake.chmod(0o700)
            self.assertEqual(70, bridge.read_codex(str(fake))[0]['remainingPercent'])

    def test_helper_stdout_needs_no_snapshot_folder(self):
        import subprocess, sys
        result = subprocess.run([sys.executable, str(Path(__file__).parents[1]/'usage_bridge.py'),
                                 '--stdout', '--no-codex'], capture_output=True, text=True, check=True)
        document = json.loads(result.stdout)
        self.assertEqual(1, document['schemaVersion'])
        self.assertTrue(all(p['state'] == 'notConnected' for p in document['providers']))

    def test_managed_kimi_reuses_server_without_starting_process(self):
        with patch.object(bridge.shutil, 'which', return_value='/fake/kimi'), \
             patch.object(bridge, 'read_kimi', return_value=[{'id': 'window'}]), \
             patch.object(bridge.subprocess, 'Popen') as process:
            self.assertEqual([{'id': 'window'}], bridge.read_managed_kimi())
            process.assert_not_called()

    def test_managed_kimi_stops_only_its_own_server(self):
        with patch.object(bridge.shutil, 'which', return_value='/fake/kimi'), \
             patch.object(bridge, 'read_kimi', side_effect=[OSError('offline'), [{'id': 'window'}]]), \
             patch.object(bridge.subprocess, 'Popen') as process:
            process.return_value.poll.return_value = None
            self.assertEqual([{'id': 'window'}], bridge.read_managed_kimi())
            process.return_value.terminate.assert_called_once()
            process.return_value.wait.assert_called_once()


    def test_provider_menu_actions_have_declared_implemented_handlers(self):
        import re
        root = Path(__file__).resolve().parents[3]
        menu = (root/'KeepingYouAwake/KYAMainMenu/KYAMainMenu.m').read_text()
        header = (root/'KeepingYouAwake/KYAAppController/KYAAppController.h').read_text()
        controller = (root/'KeepingYouAwake/KYAAppController/KYAAppController.m').read_text()
        actions = re.findall(r'initWithTitle:@"Connect [^"\n]+" action:@selector\((\w+:)\)', menu)
        self.assertEqual({'toggleCodexConnection:', 'toggleKimiConnection:'}, set(actions))
        for action in actions:
            self.assertIn('(IBAction)' + action, header)
            self.assertIn('(IBAction)' + action, controller)
            self.assertIn('item.action == @selector(' + action + ')', controller)



if __name__ == '__main__':
    unittest.main()
