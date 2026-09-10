import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from unittest.mock import patch

from pixellab_mcp import execute, save_json


class FakeClient:
    def __init__(self, fail=False):
        self.calls = 0
        self.fail = fail

    def call(self, name, arguments):
        self.calls += 1
        if self.fail:
            raise TimeoutError('Server may have accepted the request')
        return {'content': [{'type': 'text', 'text': 'id: test-character'}]}


class SubmissionReceiptTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.receipt = Path(self.folder.name) / 'receipt.json'
        self.args = {'description': 'test traveler'}

    def test_resume_reuses_successful_creation_without_another_call(self):
        client = FakeClient()
        first = execute(client, 'create_character', self.args, self.receipt)
        second = execute(client, 'create_character', self.args, self.receipt)
        self.assertEqual(first, second)
        self.assertEqual(client.calls, 1)

    def test_timeout_is_recorded_and_blocks_unchecked_resubmission(self):
        client = FakeClient(fail=True)
        with self.assertRaises(TimeoutError):
            execute(client, 'create_character', self.args, self.receipt)
        self.assertEqual(json.loads(self.receipt.read_text())['status'], 'submission_unknown')
        with self.assertRaises(RuntimeError):
            execute(client, 'create_character', self.args, self.receipt)
        self.assertEqual(client.calls, 1)

    def test_changed_prompt_cannot_overwrite_an_existing_creation_receipt(self):
        client = FakeClient()
        execute(client, 'create_character', self.args, self.receipt)
        with self.assertRaises(ValueError):
            execute(client, 'create_character', {'description': 'different'}, self.receipt)
        self.assertEqual(client.calls, 1)

    def test_status_queries_are_refreshed_instead_of_cached(self):
        client = FakeClient()
        execute(client, 'get_character', {}, self.receipt)
        execute(client, 'get_character', {}, self.receipt)
        self.assertEqual(client.calls, 2)

    def test_status_query_cannot_overwrite_creation_receipt(self):
        client = FakeClient()
        execute(client, 'create_character', self.args, self.receipt)
        original = self.receipt.read_bytes()
        with self.assertRaises(ValueError):
            execute(client, 'get_character', {}, self.receipt)
        self.assertEqual(self.receipt.read_bytes(), original)
        self.assertEqual(client.calls, 1)

    def test_concurrent_creations_claim_one_receipt_before_calling_server(self):
        client, barrier = FakeClient(), Barrier(2)

        def synchronized_save(path, value, **kwargs):
            if value['status'] == 'submitting':
                barrier.wait(timeout=5)
            save_json(path, value, **kwargs)

        def submit():
            try:
                return execute(client, 'create_character', self.args, self.receipt)
            except RuntimeError:
                return None  # A concurrent or incomplete receipt must fail closed.

        with patch('pixellab_mcp.save_json', side_effect=synchronized_save):
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: submit(), range(2)))
        self.assertEqual(client.calls, 1)
        self.assertTrue(any(result is not None for result in results))
        self.assertEqual(json.loads(self.receipt.read_text())['status'], 'returned')

    def test_incomplete_receipt_blocks_resubmission(self):
        client = FakeClient()
        self.receipt.write_text('')
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            execute(client, 'animate_character', {}, self.receipt)
        self.assertEqual(client.calls, 0)


if __name__ == '__main__':
    unittest.main()
