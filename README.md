# orders

A small FastAPI service that keeps orders in memory. Restarting it clears all orders.

## APIs

| Method | Path | What it does |
|---|---|---|
| POST | `/orders` | Create an order, e.g. `{"item": "book", "quantity": 2}` → 201 |
| GET | `/orders/{id}` | Get one order (404 if it doesn't exist) |
| GET | `/orders` | List all orders |
| GET | `/healthz` | Liveness check → `{"status": "ok"}` |
| GET | `/version` | Running version, taken from the `APP_VERSION` env var |

Interactive docs: http://localhost:8000/docs

## Run locally

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

## Run with Docker

```bash
docker build -t orders:0.1.0 .
docker run --rm -p 8000:8000 orders:0.1.0
```

To override the version: `docker run --rm -p 8000:8000 -e APP_VERSION=0.2.0 orders:0.1.0`

## Try it

```bash
curl -X POST localhost:8000/orders -H "Content-Type: application/json" -d '{"item":"book","quantity":2}'
curl localhost:8000/orders/1
curl localhost:8000/orders
curl localhost:8000/healthz
curl localhost:8000/version
```
