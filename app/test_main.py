import os
import pytest
from fastapi.testclient import TestClient

# Ensure S3 local mock directory is created
os.makedirs("s3_mock", exist_ok=True)

# Import the FastAPI app
from main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data

def test_read_items():
    response = client.get("/api/v1/items")
    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 2
    assert data[0]["name"] == "Cloud Sandbox"

def test_crud_lifecycle():
    # 1. Create item
    new_item = {
        "name": "Unit Test Item",
        "description": "Created during automated testing",
        "price": 49.99
    }
    response = client.post("/api/v1/items", json=new_item)
    assert response.status_code == 201
    created = response.json()
    item_id = created["id"]
    assert created["name"] == new_item["name"]
    assert created["price"] == new_item["price"]

    # 2. Read item
    response = client.get(f"/api/v1/items/{item_id}")
    assert response.status_code == 200
    assert response.json()["name"] == new_item["name"]

    # 3. Update item
    updated_item = {
        "name": "Updated Unit Test Item",
        "description": "Modified description",
        "price": 59.99
    }
    response = client.put(f"/api/v1/items/{item_id}", json=updated_item)
    assert response.status_code == 200
    assert response.json()["name"] == updated_item["name"]
    assert response.json()["price"] == updated_item["price"]

    # 4. Delete item
    response = client.delete(f"/api/v1/items/{item_id}")
    assert response.status_code == 200
    assert response.json()["message"] == "Item deleted"

    # 5. Verify deleted
    response = client.get(f"/api/v1/items/{item_id}")
    assert response.status_code == 404

def test_metrics_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200
    data = response.json()
    assert "system" in data
    assert "cpu_utilization_percent" in data["system"]
    assert "memory_utilization_percent" in data["system"]

def test_dashboard_renders():
    response = client.get("/")
    assert response.status_code == 200
    assert "CloudOps Live Dashboard" in response.text

def test_cpu_spike_endpoint():
    # Test with normal duration
    response = client.post("/api/v1/cpu-spike?duration=5")
    assert response.status_code == 200
    assert "CPU spike thread started" in response.json()["message"]

    # Test validation (duration > 60)
    response = client.post("/api/v1/cpu-spike?duration=65")
    assert response.status_code == 400
    assert response.json()["detail"] == "Duration cannot exceed 60 seconds"
