"""Benchmark fixture with a reproducible async reservation race."""
import asyncio


class Inventory:
    def __init__(self, stock):
        self.stock = stock

    async def reserve(self, quantity):
        available = self.stock
        if available < quantity:
            return False
        await asyncio.sleep(0)
        self.stock = available - quantity
        return True
