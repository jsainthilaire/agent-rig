"""Small benchmark fixture; deliberately incomplete input validation."""
from decimal import Decimal


def total_price(unit_price: Decimal, quantity: int) -> Decimal:
    return (unit_price * quantity).quantize(Decimal("0.01"))
