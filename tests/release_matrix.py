"""运行 python3 tests/release_matrix.py 验证二进制发布矩阵。"""
import runpy
import unittest
from pathlib import Path

select_versions = runpy.run_path(str(Path(__file__).resolve().parents[1] / "tools/release_matrix.py"))["select_versions"]


class ReleaseMatrixTest(unittest.TestCase):
    tags = ["1.100.0", "1.99.3", "1.98.0"]

    def test_numbers_ranges_and_existing_versions(self):
        self.assertEqual(select_versions("1.98.0-1.100.0,1.99.3", self.tags, ["1.99.3"]),
                         ["1.98.0", "1.100.0"])
        self.assertEqual(select_versions("", self.tags, [self.tags[0]]), ["skip"])

    def test_invalid_input(self):
        for invalid in ["1.2.3'", "1.2.3\n", ",1.2.3", "1.2.3,", "1.10.0-1.9.0"]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                select_versions(invalid, self.tags, [])


if __name__ == "__main__":
    unittest.main()
