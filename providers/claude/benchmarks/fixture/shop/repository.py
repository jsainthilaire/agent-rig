"""Benchmark persistence layer; callers must enforce tenant authorization."""
import sqlite3


SCHEMA = "CREATE TABLE orders (id INTEGER PRIMARY KEY, tenant_id INTEGER, reference TEXT)"


def find_order(connection: sqlite3.Connection, order_id: int):
    return connection.execute("SELECT id, tenant_id, reference FROM orders WHERE id = ?", (order_id,)).fetchone()
