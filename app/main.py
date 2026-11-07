import os
from itertools import count
from threading import Lock

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

VERSION = os.getenv("APP_VERSION", "0.1.0")

app = FastAPI(title="orders", version=VERSION)


class OrderIn(BaseModel):
    item: str = Field(min_length=1)
    quantity: int = Field(gt=0)


class Order(OrderIn):
    id: int


# In-memory store: data is lost on restart and not shared between replicas.
_orders: dict[int, Order] = {}
_ids = count(1)
_lock = Lock()


@app.post("/orders", response_model=Order, status_code=201)
def create_order(body: OrderIn) -> Order:
    with _lock:
        order = Order(id=next(_ids), **body.model_dump())
        _orders[order.id] = order
    return order


@app.get("/orders/{order_id}", response_model=Order)
def get_order(order_id: int) -> Order:
    order = _orders.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="order not found")
    return order


@app.get("/orders", response_model=list[Order])
def list_orders() -> list[Order]:
    return list(_orders.values())


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict:
    return {"version": VERSION}
