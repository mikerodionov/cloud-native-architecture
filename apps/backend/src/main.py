import os
import psycopg2
from fastapi import FastAPI
from fastapi.responses import Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = FastAPI()

# Database Configuration (Injected via Kubernetes Secrets/ConfigMaps later)
DB_HOST = os.getenv("DB_HOST", "postgres-db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASSWORD", "postgres")
DB_NAME = os.getenv("DB_NAME", "appdb")

def get_db_connection():
    try:
        conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, dbname=DB_NAME, connect_timeout=3)
        return conn
    except Exception as e:
        print(f"Database connection failed: {e}")
        return None

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    """Exposes application-level metrics for Prometheus scraping"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/api/data")
def get_data():
    conn = get_db_connection()
    if not conn:
        return {"service": "backend", "db_status": "disconnected (running in degraded mode)"}
    
    # Simulating a successful transactional flow
    conn.close()
    return {"service": "backend", "db_status": "connected"}