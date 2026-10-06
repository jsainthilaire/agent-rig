"""Existing fixture tests intentionally omit the seeded defects."""
from decimal import Decimal
import unittest
from shop.api import quote


class QuoteTests(unittest.TestCase):
    def test_normal_quantity(self):
        self.assertEqual(quote(Decimal("2.50"), 3), Decimal("7.50"))


if __name__ == "__main__":
    unittest.main()
