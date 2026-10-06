"""Benchmark entrypoints with a missing tenant ownership check."""
from .pricing import total_price
from .repository import find_order


def quote(unit_price, quantity):
    return total_price(unit_price, quantity)


def order_details(connection, authenticated_tenant_id, order_id):
    return find_order(connection, order_id)
