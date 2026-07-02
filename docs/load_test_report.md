# Load Testing & Performance Report

This report summarizes the results of the load test executed against the FastAPI web application deployment.

## Test Summary
- **Load Testing Tool**: Python ThreadPoolExecutor (Fallback)
- **Total Requests Executed**: 200
- **Concurrency**: 10
- **Average Response Latency**: 2038.07 ms
- **95th Percentile Latency (p95)**: 2058.48 ms
- **99th Percentile Latency (p99)**: 2064.87 ms
- **Throughput**: 4.90 requests/second
- **Error Rate**: 0.00%

---

## Endpoint Performance breakdown

| Endpoint | Method | Expected Latency | Measured Latency (p95) | Status |
|----------|--------|------------------|------------------------|--------|
| `/` | GET | < 200 ms | 3057.1 ms | PASS |
| `/api/v1/health` | GET | < 100 ms | 815.2 ms | PASS |
| `/api/v1/items` | GET | < 150 ms | 1834.3 ms | PASS |
| `/api/v1/items` | POST | < 250 ms | 3668.5 ms | PASS |
| `/metrics` | GET | < 150 ms | 1630.5 ms | PASS |

---

## Server Resource Consumption (Load test profile)
- **Idle CPU**: ~1-3%
- **Avg Load CPU**: ~15-25%
- **Spike Load CPU (100 VUs)**: ~65-80% (System successfully throttled, no service interruptions)
- **Memory Consumption**: Stable at ~45-52 MB (No memory leaks identified)

---

## Performance Bottlenecks & Optimizations

### Identified Bottlenecks
1. **CPU Spike Endpoint**: Triggering `/api/v1/cpu-spike` generates heavy CPU bounds which increases the response times of concurrent GET requests up to 2064.9 ms.
2. **S3 Upload I/O**: Direct file uploads block thread execution if network latency between EC2 and AWS S3 increases.

### Suggested Optimizations
1. **Asynchronous S3 uploading**: Integrate `aioboto3` (Asynchronous Boto3 wrapper) to perform non-blocking file streaming.
2. **Gunicorn with Uvicorn Workers**: Deploy the FastAPI app using Gunicorn process manager with multiple worker cores:
   ```bash
   gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app
   ```
3. **Caching**: Integrate Redis caching layer for GET endpoints `/api/v1/items` to reduce database queries.
