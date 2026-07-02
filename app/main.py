import os
import time
import logging
import threading
from typing import Dict, List, Optional
from fastapi import FastAPI, Request, File, UploadFile, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
import psutil
import boto3
from botocore.exceptions import NoCredentialsError, ClientError

# Setup logging to stdout and local file app.log
log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
logging.basicConfig(level=logging.INFO, format=log_format)
logger = logging.getLogger("devops-app")

file_handler = logging.FileHandler("app.log")
file_handler.setFormatter(logging.Formatter(log_format))
logger.addHandler(file_handler)

app = FastAPI(
    title="DevOps Web Application API",
    description="Production-ready FastAPI app with S3 integration, CloudWatch metrics, and load testing capabilities.",
    version="1.0.0"
)

# In-memory mock database
items_db: Dict[int, dict] = {
    1: {"id": 1, "name": "Cloud Sandbox", "description": "AWS Free Tier testing environment.", "price": 0.0},
    2: {"id": 2, "name": "Load Test Agent", "description": "k6 agent container.", "price": 19.99},
}

class Item(BaseModel):
    name: str
    description: Optional[str] = None
    price: float

# S3 Configuration
S3_BUCKET = os.getenv("AWS_S3_BUCKET", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
s3_client = None

# Initialize S3 client if variables are present, otherwise mock S3 operations
if S3_BUCKET:
    try:
        s3_client = boto3.client("s3", region_name=AWS_REGION)
        logger.info(f"S3 client initialized for bucket: {S3_BUCKET}")
    except Exception as e:
        logger.error(f"Failed to initialize S3 client: {e}")
else:
    logger.info("No S3 bucket configured via AWS_S3_BUCKET. S3 operations will use local mock storage.")
    os.makedirs("s3_mock", exist_ok=True)

# Templates setup
templates = Jinja2Templates(directory="templates")

# Middleware to calculate response time (latency)
@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    logger.info(f"Request: {request.method} {request.url.path} - Status: {response.status_code} - Latency: {process_time:.4f}s")
    return response

# Dashboard frontend router
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    # Fetch system metrics
    cpu_percent = psutil.cpu_percent(interval=None)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    
    # Load files from S3 or local mock
    files = []
    storage_mode = "AWS S3" if s3_client else "Local Mock (s3_mock/)"
    if s3_client:
        try:
            response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
            if "Contents" in response:
                files = [{"key": obj["Key"], "size": obj["Size"], "modified": str(obj["LastModified"])} for obj in response["Contents"]]
        except Exception as e:
            logger.warning(f"Could not list S3 files (using local mock fallback): {e}")
            storage_mode += " (Authentication Failed)"
    
    if not s3_client or "Authentication Failed" in storage_mode:
        # Fallback to listing local mock files
        if os.path.exists("s3_mock"):
            for f in os.listdir("s3_mock"):
                fp = os.path.join("s3_mock", f)
                stat = os.stat(fp)
                files.append({
                    "key": f,
                    "size": stat.st_size,
                    "modified": str(time.ctime(stat.st_mtime))
                })

    metrics = {
        "cpu": cpu_percent,
        "memory_percent": memory.percent,
        "memory_used": f"{memory.used / (1024**3):.2f} GB / {memory.total / (1024**3):.2f} GB",
        "disk_percent": disk.percent,
        "storage_mode": storage_mode,
        "s3_bucket_name": S3_BUCKET or "N/A (Local Mocking Active)"
    }

    return templates.TemplateResponse("index.html", {
        "request": request, 
        "metrics": metrics, 
        "items": list(items_db.values()),
        "files": files
    })

# API Endpoints
@app.get("/api/v1/health")
async def health_check():
    logger.info("Health check endpoint hit")
    return {
        "status": "healthy",
        "timestamp": time.time(),
        "app_name": "DevOps Technical Assignment App",
        "version": "1.0.0"
    }

# CRUD - Read List
@app.get("/api/v1/items", response_model=List[dict])
async def read_items():
    return list(items_db.values())

# CRUD - Read Item
@app.get("/api/v1/items/{item_id}")
async def read_item(item_id: int):
    if item_id not in items_db:
        logger.warning(f"Item not found: {item_id}")
        raise HTTPException(status_code=404, detail="Item not found")
    return items_db[item_id]

# CRUD - Create
@app.post("/api/v1/items", status_code=201)
async def create_item(item: Item):
    new_id = max(items_db.keys()) + 1 if items_db else 1
    items_db[new_id] = {
        "id": new_id,
        "name": item.name,
        "description": item.description,
        "price": item.price
    }
    logger.info(f"Item created: ID {new_id}, Name {item.name}")
    return items_db[new_id]

# CRUD - Update
@app.put("/api/v1/items/{item_id}")
async def update_item(item_id: int, item: Item):
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    items_db[item_id].update({
        "name": item.name,
        "description": item.description,
        "price": item.price
    })
    logger.info(f"Item updated: ID {item_id}")
    return items_db[item_id]

# CRUD - Delete
@app.delete("/api/v1/items/{item_id}")
async def delete_item(item_id: int):
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    deleted_item = items_db.pop(item_id)
    logger.info(f"Item deleted: ID {item_id}")
    return {"message": "Item deleted", "item": deleted_item}

# S3 File Upload Endpoint
@app.post("/api/v1/upload")
async def upload_file(file: UploadFile = File(...)):
    filename = file.filename
    if s3_client:
        try:
            s3_client.upload_fileobj(
                file.file,
                S3_BUCKET,
                filename,
                ExtraArgs={"ContentType": file.content_type}
            )
            logger.info(f"Successfully uploaded {filename} to AWS S3 Bucket {S3_BUCKET}")
            return {"status": "success", "message": f"Uploaded {filename} to S3", "filename": filename}
        except ClientError as e:
            logger.error(f"S3 Client Error uploading {filename}: {e}")
            raise HTTPException(status_code=500, detail=f"S3 Upload failed: {e}")
        except Exception as e:
            logger.error(f"Error uploading {filename}: {e}")
            raise HTTPException(status_code=500, detail=f"Upload failed: {e}")
    else:
        # Save locally in mock storage
        try:
            file_path = os.path.join("s3_mock", filename)
            with open(file_path, "wb") as f:
                f.write(await file.read())
            logger.info(f"Mock S3 Upload: Saved {filename} to s3_mock/")
            return {"status": "success", "message": f"Uploaded {filename} to Local Mock Storage", "filename": filename}
        except Exception as e:
            logger.error(f"Mock S3 Upload failed: {e}")
            raise HTTPException(status_code=500, detail=f"Mock upload failed: {e}")

# CPU Intensive Endpoint to test CloudWatch Alarm and Load Testing
def load_generator(duration: int):
    start = time.time()
    # Perform math in a loop to spike CPU
    while time.time() - start < duration:
        _ = 12345 * 67890

@app.post("/api/v1/cpu-spike")
async def cpu_spike(duration: int = 10):
    if duration > 60:
        raise HTTPException(status_code=400, detail="Duration cannot exceed 60 seconds")
    
    logger.info(f"Spiking CPU for {duration} seconds...")
    # Spawn background thread to generate CPU spikes so we don't block the async event loop
    thread = threading.Thread(target=load_generator, args=(duration,))
    thread.daemon = True
    thread.start()
    
    return {"status": "success", "message": f"CPU spike thread started for {duration} seconds"}

# System Metrics Endpoint for direct scraping/monitoring
@app.get("/metrics")
async def get_metrics():
    cpu_percent = psutil.cpu_percent(interval=None)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    
    return {
        "system": {
            "cpu_utilization_percent": cpu_percent,
            "memory_utilization_percent": memory.percent,
            "memory_free_bytes": memory.free,
            "memory_total_bytes": memory.total,
            "disk_utilization_percent": disk.percent,
            "disk_free_bytes": disk.free
        },
        "app": {
            "items_count": len(items_db),
            "storage_provider": "AWS S3" if s3_client else "Mock S3 (local)"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
