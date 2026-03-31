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
- Routing: React Router + UmiJS conventions
- Visualization: AntV G6 (graph), AntV G2 (charts), Recharts
- Editors: Monaco Editor, Lexical rich text
- i18n: i18next
- Key pages in `web/src/pages/`: home, login-next, datasets, dataset, documents, agents, agent, next-chats, next-search, memories, user-setting, admin
- Reusable components in `web/src/components/` (40+ directories)

### Memory Module (`/memory/`)
- Message and query services with connectors for ES, Infinity, OceanBase
- `memory/services/`, `memory/utils/`

### MCP Module (`/mcp/`)
- Model Context Protocol implementation

### SDK (`/sdk/python/`)
- Python SDK: `sdk/python/ragflow_sdk/`
- SDK tests: `sdk/python/test/`

### Common Utilities (`/common/`)
- `common/settings.py` — global configuration
- `common/data_source/` — data source connectors
- `common/doc_store/` — document storage interfaces
- Crypto, HTTP client, logging, prompt logger, metadata utilities

### Admin CLI (`/admin/`)
- `admin/client/COMMAND.md` — CLI documentation
- `admin/build_cli_release.sh` — release build

## Common Development Commands

### Backend Development
```bash
# Install Python dependencies (Python 3.12 required)
uv sync --python 3.12 --all-extras
uv run download_deps.py
pre-commit install

# Start dependent services (MySQL, Elasticsearch, Redis, MinIO)
docker compose -f docker/docker-compose-base.yml up -d

# Run backend (requires services running)
source .venv/bin/activate
export PYTHONPATH=$(pwd)
bash docker/launch_backend_service.sh

# Run tests
uv run pytest                        # all tests
python run_tests.py                  # test runner with CLI
python run_tests.py --coverage       # with coverage report
python run_tests.py --parallel       # parallel execution
python run_tests.py --markers "p1"   # by priority marker (p0/p1/p2/p3)
uv run pytest test/unit_test/        # unit tests only

# Linting
ruff check
ruff format
```

### Frontend Development
```bash
cd web
npm install
npm run dev        # Development server
npm run build      # Production build
npm run lint       # ESLint
npm run test       # Jest tests
```

### Docker Development
```bash
# Start full stack (default: Elasticsearch engine)
docker compose -f docker/docker-compose.yml up -d

# Start with a specific vector DB engine
DOC_ENGINE=infinity docker compose -f docker/docker-compose.yml up -d

# Check server status
docker logs -f ragflow-server

# Rebuild image
docker build --platform linux/amd64 -f Dockerfile -t infiniflow/ragflow:nightly .

# Stop and remove volumes (needed when changing DOC_ENGINE)
docker compose down -v && docker compose up -d
```

### Go Development
```bash
# Run Go tests
bash run_go_tests.sh
```

## Key Configuration Files

| File | Purpose |
|------|---------|
| `docker/.env` | Docker environment variables (passwords, ports, engine selection) |
| `docker/service_conf.yaml.template` | Backend service configuration template |
| `conf/service_conf.yaml` | Active service configuration |
| `conf/llm_factories.json` | LLM provider and model configurations (230 KB) |
| `conf/system_settings.json` | System-level defaults |
| `conf/mapping.json` | Elasticsearch index mapping |
| `pyproject.toml` | Python dependencies and project configuration |
| `web/package.json` | Frontend dependencies and scripts |
| `.pre-commit-config.yaml` | Pre-commit hooks (ruff, format checks) |
| `go.mod` | Go module dependencies |

## Testing

- **Python**: pytest with priority markers p0 (critical), p1 (high), p2 (medium), p3 (low), plus `smoke`, `auth`, `asyncio`
- **Frontend**: Jest with React Testing Library
- **E2E/Browser**: Playwright tests in `test/playwright/`
- **Benchmarks**: `test/benchmark/`
- **API Tests**: `test/testcases/` (integration), `sdk/python/test/` (SDK)
- **Unit Tests**: `test/unit_test/` organized by module (api, common, deepdoc, memory, rag)
- **Agent Tests**: `agent/test/` and `agent/component/test/`

## Database & Vector Engine Options

RAGFlow supports multiple vector/document engines, set via `DOC_ENGINE` in `docker/.env`:

| Engine | Value | Notes |
|--------|-------|-------|
| Elasticsearch | `elasticsearch` (default) | ES_PORT=1200 |
| Infinity | `infinity` | INFINITY_HOST=infinity, ports 23817/23820 |
| OpenSearch | `opensearch` | OS_HOST=opensearch01, port 1201 |
| OceanBase | `oceanbase` | OCEANBASE_HOST=oceanbase, port 2881 |
| SeekDB | `seekdb` | SEEKDB_HOST=seekdb, port 2881 |

Changing `DOC_ENGINE` requires: `docker compose down -v && docker compose up -d`

Relational DB: MySQL (port 3306). Object storage: MinIO.

## LLM Providers

Integrated via `litellm` (~1.82.0). Supported providers include: OpenAI, Anthropic, Cohere, Groq, Mistral, Ollama, DashScope (Alibaba), ZhipuAI, Qianfan (Baidu), and 20+ others. Configuration in `conf/llm_factories.json` and `api/db/services/llm_service.py`.

## Development Environment Requirements

- Python 3.12 (required; range >=3.12,<3.15)
- Node.js >=18.20.4
- Go 1.25.0 (for internal/ microservices)
- Docker & Docker Compose
- `uv` package manager
- 16GB+ RAM, 50GB+ disk space
- GPU optional (set `DEVICE=gpu` in `docker/.env`; defaults to `cpu`)
