import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('migration', Path(__file__).parents[1] / 'migrate.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class PasswordCSVTests(unittest.TestCase):
    def read_rows(self, fields, rows):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'passwords.csv'
            with path.open('w', encoding='utf-8-sig', newline='') as stream:
                writer = csv.writer(stream)
                writer.writerow(fields)
                writer.writerows(rows)
            return migration.read_password_csv(path)

    def test_browser_csv_preserves_credentials_and_reports_internal_rows(self):
        entries, skipped = self.read_rows(['name', 'url', 'username', 'password', 'note'], [
            ['Example', 'https://example.invalid/login', 'demo', 'comma, quote"\nпароль', ''],
            ['Internal', 'vivaldi://settings', '', 'internal', ''],
        ])
        self.assertEqual(entries, [{'origin': 'https://example.invalid/login', 'username': 'demo', 'password': 'comma, quote"\nпароль'}])
        self.assertEqual(skipped, 1)

    def test_rejects_missing_columns_empty_password_and_embedded_credentials(self):
        for fields, rows in [
            (['url', 'username'], [['https://example.invalid', 'demo']]),
            (['url', 'username', 'password'], [['https://example.invalid', 'demo', '']]),
            (['url', 'username', 'password'], [['https://user:secret@example.invalid', 'demo', 'secret']]),
        ]:
            with self.assertRaises(ValueError):
                self.read_rows(fields, rows)


if __name__ == '__main__':
    unittest.main()
