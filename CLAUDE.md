# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RAGFlow is an open-source RAG (Retrieval-Augmented Generation) engine based on deep document understanding. It's a full-stack application with:
- Python backend (Flask-based API server, Python >=3.12)
- React/TypeScript frontend (Vite + UmiJS framework)
- Go microservices (`internal/`) for search engine and storage abstractions
- Microservices architecture with Docker deployment
- Multiple data stores: MySQL, Elasticsearch/Infinity/OpenSearch/OceanBase/SeekDB, Redis, MinIO

## Architecture

### Backend (`/api/`)
- **Main Server**: `api/ragflow_server.py` — Flask app entry point
- **Blueprints**: `api/apps/` — one file per feature area:
  - `kb_app.py` — Knowledge base management
  - `dialog_app.py` — Chat/conversation handling
  - `document_app.py` — Document processing
  - `canvas_app.py` — Agent workflow canvas
  - `chunk_app.py` — Chunking configuration
  - `connector_app.py` — Data connectors
  - `llm_app.py` — LLM configuration
  - `mcp_server_app.py` — MCP server
  - `plugin_app.py` — Plugin system
  - `evaluation_app.py` — Evaluation
  - `file_app.py`, `file2document_app.py` — File upload/management
  - `user_app.py`, `tenant_app.py`, `system_app.py` — User/tenant management
  - `langfuse_app.py` — Langfuse integration
- **Services**: Business logic in `api/db/services/` (24 service files)
- **Models**: Peewee ORM database models in `api/db/db_models.py`

### Core Processing (`/rag/`)
- **LLM Abstractions**: `rag/llm/` — chat, embedding, CV, rerank, OCR, TTS, seq2txt models
- **Pipeline**: `rag/flow/` — document parsers, chunking splitters, tokenizers, extractors
- **Graph RAG**: `rag/graphrag/general/` and `rag/graphrag/light/`
- **Advanced RAG**: `rag/advanced_rag/`
- **Prompts**: `rag/prompts/` — 70+ Markdown prompt templates
- **NLP Utilities**: `rag/nlp/`

### Document Processing (`/deepdoc/`)
- PDF parsing, OCR, layout analysis — used by both backend and RAG pipeline

### Agent System (`/agent/`)
- **Components**: `agent/component/` — 22 workflow node types (LLM, message, retrieval, categorize, loop, switch, etc.)
- **Tools**: `agent/tools/` — 23 external integrations (Tavily, Wikipedia, arXiv, DuckDuckGo, Google, email, SQL, GitHub, etc.)
- **Templates**: `agent/templates/` — 24 pre-built workflow JSONs (web search, customer service, deep research, stock research, etc.)
- **Sandbox**: `agent/sandbox/` — isolated code execution environment
- **Plugins**: `agent/plugin/`

### Go Microservices (`/internal/`)
- Go 1.25.0, uses Gin framework and GORM ORM
- Search engine abstraction layer: `internal/engine/` (elasticsearch, infinity, types)
- Storage layer: `internal/storage/`
- Admin services: `internal/admin/`
- C++ bindings: `internal/cpp/` (stemmer, re2, opencc, darts)

### Frontend (`/web/`)
- React 18 + TypeScript 5.9 with Vite 7
- Ant Design + shadcn/ui (Radix UI) components
- State management: Zustand + TanStack React Query
- Visualization: AntV G6 (graph), AntV G2 (charts), Recharts
- Editors: Monaco Editor, Lexical rich text
- i18n: i18next
- Key pages in `web/src/pages/`: home, login-next, datasets, dataset, documents, agents, agent, next-chats, next-search, memories, user-setting, admin
- Reusable components in `web/src/components/` (40+ directories)

### Memory Module (`/memory/`)
- Message and query services with connectors for ES, Infinity, OceanBase
- `memory/services/`, `memory/utils/`

### MCP Module (`/mcp/`)
- Model Context Protocol server implementation

### SDK (`/sdk/python/`)
- Python SDK: `sdk/python/ragflow_sdk/`
- SDK tests: `sdk/python/test/`

### Common Utilities (`/common/`)
- `common/settings.py` — global configuration
- `common/data_source/` — data source connectors
- `common/doc_store/` — document storage interfaces

## Running Locally (Full Setup)

### Prerequisites

| Requirement | Version |
|-------------|---------|
| Python | >=3.12, <3.15 |
| Node.js | >=18.20.4 |
| Go | 1.25.0 (optional, for internal/ services) |
| Docker & Docker Compose | latest |
| `uv` package manager | latest |
| RAM | 16GB+ |
| Disk | 50GB+ |

Install `uv`: `curl -LsSf https://astral.sh/uv/install.sh | sh`

### Option A — Full Docker Stack (Recommended)

This is the simplest way to run everything including infrastructure services.

```bash
# 1. Clone and enter the repo
git clone https://github.com/infiniflow/ragflow.git
cd ragflow

# 2. Copy and edit environment config
cp docker/.env docker/.env.local   # optional: keep originals intact
# Edit docker/.env — at minimum change passwords for non-local use

# 3. Pull images and start (default: Elasticsearch engine, CPU mode)
cd docker
docker compose -f docker-compose.yml up -d

# 4. Check status
docker logs -f ragflow-server

# 5. Open the UI
# http://localhost (port 80 by default)
```

Ports exposed by default:

| Port | Service |
|------|---------|
| 80 | Web UI (nginx) |
| 443 | Web UI HTTPS |
| 9380 | RAGFlow API |
| 9381 | Admin API |
| 9382 | MCP server |
| 1200 | Elasticsearch |
| 3306 | MySQL (not exposed by default) |

### Option B — Backend in Python + Docker Infrastructure

Use this when actively developing the Python backend.

#### Step 1: Start infrastructure services only

```bash
# Starts MySQL, Elasticsearch (or your DOC_ENGINE), Redis, MinIO
docker compose -f docker/docker-compose-base.yml up -d
```

#### Step 2: Install Python dependencies

```bash
uv sync --python 3.12 --all-extras
uv run download_deps.py   # downloads NLTK data, model weights, etc.
pre-commit install
```

#### Step 3: Configure service_conf.yaml

The backend reads `conf/service_conf.yaml`. For local development, the hosts must point to `localhost` instead of Docker service names:

```bash
# Copy the template
cp docker/service_conf.yaml.template conf/service_conf.yaml
```

Then edit `conf/service_conf.yaml` and change hosts to `localhost` / `127.0.0.1`:

```yaml
mysql:
  host: 'localhost'          # was: mysql
  port: 3306
  password: 'infini_rag_flow'

es:
  hosts: 'http://localhost:9200'   # was: http://es01:9200

minio:
  host: 'localhost:9000'     # was: minio:9000

redis:
  host: 'localhost:6379'     # was: redis:6379
```

#### Step 4: Run the backend

```bash
source .venv/bin/activate
export PYTHONPATH=$(pwd)
bash docker/launch_backend_service.sh
```

The backend starts:
- `api/ragflow_server.py` — Flask API on port 9380
- `rag/svr/task_executor.py` — document processing workers (WS workers, default 1)

To control the number of workers: `WS=4 bash docker/launch_backend_service.sh`

#### Step 5: Run the frontend dev server

```bash
cd web
npm install
npm run dev   # starts on http://localhost:8000, proxies API to localhost:9380
```

### Option C — Docker with Custom Vector DB Engine

```bash
# Use Infinity instead of Elasticsearch
DOC_ENGINE=infinity docker compose -f docker/docker-compose.yml up -d

# Use OpenSearch
DOC_ENGINE=opensearch docker compose -f docker/docker-compose.yml up -d

# Use OceanBase
DOC_ENGINE=oceanbase docker compose -f docker/docker-compose.yml up -d
```

**Important**: switching `DOC_ENGINE` requires destroying volumes:
```bash
docker compose down -v
DOC_ENGINE=infinity docker compose -f docker/docker-compose.yml up -d
```

### Option D — macOS

```bash
docker compose -f docker/docker-compose-macos.yml up -d
```

### Option E — GPU Acceleration (deepdoc inference)

```bash
# Edit docker/.env
DEVICE=gpu
# Then restart
docker compose -f docker/docker-compose.yml up -d
```

Or for local backend: the `DEVICE=gpu` env var is read from `docker/.env` by `launch_backend_service.sh`.

## Docker Environment Configuration (`docker/.env`)

Key variables to configure before running:

```bash
# Vector DB engine (elasticsearch | infinity | oceanbase | opensearch | seekdb)
DOC_ENGINE=elasticsearch

# Inference device (cpu | gpu)
DEVICE=cpu

# Passwords — CHANGE THESE for any non-local deployment
ELASTIC_PASSWORD=infini_rag_flow
MYSQL_PASSWORD=infini_rag_flow
MINIO_PASSWORD=infini_rag_flow
REDIS_PASSWORD=infini_rag_flow

# Memory limit per container (bytes), default 8GB
MEM_LIMIT=8073741824

# Secret key for session signing (generate with: openssl rand -hex 32)
RAGFLOW_SECRET_KEY=ab2b9c8f...

# Allow user self-registration (1=yes, 0=no)
REGISTER_ENABLED=1

# Document processing batch sizes
DOC_BULK_SIZE=4
EMBEDDING_BATCH_SIZE=16

# LLM call timeouts (seconds)
LLM_TIMEOUT_SECONDS=1200
LLM_TEST_TIMEOUT_SECONDS=120

# Log level (DEBUG | INFO | WARNING | ERROR)
# LOG_LEVELS=ragflow.es_conn=DEBUG

# Enable sandbox for code execution in agents
# SANDBOX_ENABLED=1
# COMPOSE_PROFILES=${COMPOSE_PROFILES},sandbox

# Optional: use DocLing for PDF parsing
USE_DOCLING=false

# Optional: Aliyun OSS instead of MinIO
# STORAGE_IMPL=OSS
# ACCESS_KEY=xxx
# SECRET_KEY=xxx
# ENDPOINT=http://oss-cn-hangzhou.aliyuncs.com
# REGION=cn-hangzhou
# BUCKET=ragflow65536
```

## Service Configuration (`conf/service_conf.yaml`)

Generated from `docker/service_conf.yaml.template`. Key sections:

```yaml
ragflow:
  host: 0.0.0.0
  http_port: 9380

mysql:
  name: rag_flow
  user: root
  password: infini_rag_flow
  host: mysql          # use 'localhost' for local dev (Option B)
  port: 3306

es:
  hosts: 'http://es01:9200'   # use 'http://localhost:9200' for local dev
  username: elastic
  password: infini_rag_flow

minio:
  user: rag_flow
  password: infini_rag_flow
  host: 'minio:9000'          # use 'localhost:9000' for local dev

redis:
  db: 1
  password: infini_rag_flow
  host: 'redis:6379'          # use 'localhost:6379' for local dev
```

## Common Development Commands

### Backend Development

```bash
# Install Python dependencies
uv sync --python 3.12 --all-extras
uv run download_deps.py
pre-commit install

# Start infrastructure only
docker compose -f docker/docker-compose-base.yml up -d

# Run backend
source .venv/bin/activate
export PYTHONPATH=$(pwd)
bash docker/launch_backend_service.sh

# Run tests
uv run pytest                        # all tests
python run_tests.py                  # CLI test runner
python run_tests.py --coverage       # with coverage report
python run_tests.py --parallel       # parallel execution
python run_tests.py --markers "p1"   # by priority (p0/p1/p2/p3)
uv run pytest test/unit_test/        # unit tests only

# Linting
ruff check
ruff format
```

### Frontend Development

```bash
cd web
npm install
npm run dev        # Development server (http://localhost:8000)
npm run build      # Production build
npm run lint       # ESLint
npm run test       # Jest tests
```

### Docker Development

```bash
# Full stack
docker compose -f docker/docker-compose.yml up -d

# Check status
docker logs -f ragflow-server

# Stop all
docker compose -f docker/docker-compose.yml down

# Stop and remove volumes (needed after changing DOC_ENGINE)
docker compose -f docker/docker-compose.yml down -v

# Rebuild image from source
docker build --platform linux/amd64 -f Dockerfile -t infiniflow/ragflow:nightly .
```

### entrypoint.sh CLI flags (inside container)

```bash
# Default: web server + task executors + data sync
./entrypoint.sh

# Only web server (no task executors)
./entrypoint.sh --disable-taskexecutor

# Only task executors (no web server), e.g. for worker scaling
./entrypoint.sh --disable-webserver --workers=4

# Task executors with range-based IDs
./entrypoint.sh --disable-webserver --consumer-no-beg=0 --consumer-no-end=5

# Enable MCP server
./entrypoint.sh --enable-mcpserver

# Enable Admin server
./entrypoint.sh --enable-adminserver

# Initialize superuser
./entrypoint.sh --init-superuser
```

## Key Configuration Files

| File | Purpose |
|------|---------|
| `docker/.env` | Docker environment variables (passwords, ports, engine selection) |
| `docker/service_conf.yaml.template` | Backend service configuration template |
| `conf/service_conf.yaml` | Active service configuration (generated from template) |
| `conf/llm_factories.json` | LLM provider and model configurations (230 KB) |
| `conf/system_settings.json` | System-level defaults |
| `conf/mapping.json` | Elasticsearch index mapping |
| `pyproject.toml` | Python dependencies and project configuration |
| `web/package.json` | Frontend dependencies and scripts |
| `.pre-commit-config.yaml` | Pre-commit hooks (ruff, format checks) |
| `go.mod` | Go module dependencies |
| `docker/nginx/ragflow.conf` | Nginx configuration |

## Testing

- **Python**: pytest with priority markers p0 (critical), p1 (high), p2 (medium), p3 (low), plus `smoke`, `auth`, `asyncio`
- **Frontend**: Jest with React Testing Library
- **E2E/Browser**: Playwright tests in `test/playwright/`
- **Benchmarks**: `test/benchmark/`
- **API Tests**: `test/testcases/` (integration), `sdk/python/test/` (SDK)
- **Unit Tests**: `test/unit_test/` organized by module (api, common, deepdoc, memory, rag)

## Database & Vector Engine Options

| Engine | `DOC_ENGINE` value | Notes |
|--------|--------------------|-------|
| Elasticsearch | `elasticsearch` (default) | Port 1200 exposed |
| Infinity | `infinity` | Ports 23817, 23820, 5432 |
| OpenSearch | `opensearch` | Port 1201 exposed |
| OceanBase | `oceanbase` | Port 2881 |
| SeekDB | `seekdb` | Port 2881 (OceanBase lite) |

Relational DB: MySQL port 3306. Object storage: MinIO port 9000.

## LLM Providers

Integrated via `litellm` (~1.82.0). Supported providers include: OpenAI, Anthropic, Cohere, Groq, Mistral, Ollama, DashScope (Alibaba), ZhipuAI, Qianfan (Baidu), and 20+ others. Configuration in `conf/llm_factories.json` and managed via `api/db/services/llm_service.py`.
