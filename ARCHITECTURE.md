# RAGFlow Architecture

This document describes all services in the RAGFlow project, their responsibilities, and how they interconnect at the data and process level.

---

## Table of Contents

- [System Overview](#system-overview)
- [Deployment Topology](#deployment-topology)
- [Service Descriptions](#service-descriptions)
  - [Nginx (Reverse Proxy)](#nginx-reverse-proxy)
  - [RAGFlow Server (Python API)](#ragflow-server-python-api)
  - [Go Microservice (server_main)](#go-microservice-server_main)
  - [Task Executor](#task-executor)
  - [Data Source Sync Worker](#data-source-sync-worker)
  - [Admin Server](#admin-server)
  - [MCP Server](#mcp-server)
  - [MySQL](#mysql)
  - [Elasticsearch / OpenSearch / Infinity / OceanBase / SeekDB](#document-engine)
  - [MinIO (Object Storage)](#minio-object-storage)
  - [Redis (Valkey)](#redis-valkey)
  - [TEI (Text Embeddings Inference)](#tei-text-embeddings-inference)
  - [Sandbox Executor Manager](#sandbox-executor-manager)
  - [Kibana (Optional)](#kibana-optional)
- [Internal Subsystems](#internal-subsystems)
  - [RAG Core (rag/)](#rag-core)
  - [Deep Document Understanding (deepdoc/)](#deep-document-understanding)
  - [Agent / Canvas Workflow Engine (agent/)](#agent--canvas-workflow-engine)
  - [LLM Abstraction Layer (rag/llm/)](#llm-abstraction-layer)
  - [Python SDK (sdk/)](#python-sdk)
- [Data Flow Diagrams](#data-flow-diagrams)
  - [Document Ingestion Pipeline](#document-ingestion-pipeline)
  - [Query / Chat Pipeline](#query--chat-pipeline)
  - [Agent Canvas Execution](#agent-canvas-execution)
- [Network and Port Map](#network-and-port-map)
- [Configuration Files](#configuration-files)

---

## System Overview

RAGFlow is a Retrieval-Augmented Generation (RAG) engine with deep document understanding. It combines document parsing, chunking, embedding, retrieval, and LLM-powered answer generation into a full-stack application.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Client (Browser)                           │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTP/HTTPS
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Nginx (port 80/443 inside container, 8060/8443 on host)           │
│  ┌─────────────────┐  ┌────────────────┐  ┌──────────────────────┐ │
│  │ /               │  │ /v1, /api      │  │ /api/v1/admin        │ │
│  │ Static frontend │  │ → Python API   │  │ → Admin Server       │ │
│  │ (React SPA)     │  │   :9380        │  │   :9381              │ │
│  └─────────────────┘  └────────────────┘  └──────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
         │                      │                       │
         ▼                      ▼                       ▼
   React SPA            RAGFlow Server            Admin Server
   (web/dist)           (Python/Quart)            (Python/Flask)
                             │
              ┌──────────────┼─────────────────┐
              ▼              ▼                  ▼
         Go Backend     Task Executors     Data Sync Worker
        (server_main)   (rag/svr/)         (rag/svr/)
              │              │                  │
              ▼              ▼                  ▼
    ┌────────────────────────────────────────────────────┐
    │              Shared Data Stores                    │
    │  MySQL │ Elasticsearch │ Redis │ MinIO │ TEI       │
    └────────────────────────────────────────────────────┘
```

---

## Deployment Topology

All services run as Docker containers on a single bridge network (`ragflow`). The main RAGFlow container runs multiple processes (nginx, Python API, Go backend, task executors, sync workers) managed by the entrypoint script.

Docker Compose profiles control which services start:

| Profile          | Services Activated                                 |
|------------------|----------------------------------------------------|
| `cpu`            | `ragflow-cpu` (CPU-only inference)                 |
| `gpu`            | `ragflow-gpu` (NVIDIA GPU inference)               |
| `elasticsearch`  | `es01` (Elasticsearch 8.x)                         |
| `opensearch`     | `opensearch01` (OpenSearch 2.x)                    |
| `infinity`       | `infinity` (Infinity vector DB)                    |
| `oceanbase`      | `oceanbase` (OceanBase CE)                         |
| `seekdb`         | `seekdb` (SeekDB, OceanBase lite)                  |
| `tei-cpu`        | TEI embedding server (CPU)                         |
| `tei-gpu`        | TEI embedding server (GPU + NVIDIA)                |
| `kibana`         | Kibana for Elasticsearch monitoring                |
| `sandbox`        | Sandbox executor manager for safe code execution   |

---

## Service Descriptions

### Nginx (Reverse Proxy)

**Runs inside**: the RAGFlow container (`ragflow-cpu` or `ragflow-gpu`)

**Purpose**: Serves the React frontend as static files and reverse-proxies API requests to backend processes.

**Routing rules** (from `nginx/ragflow.conf`):

| Path Pattern        | Upstream             | Description                   |
|---------------------|----------------------|-------------------------------|
| `/`                 | Local filesystem     | React SPA (`/ragflow/web/dist`) |
| `/v1/*`, `/api/*`   | `localhost:9380`     | Python API server             |
| `/api/v1/admin/*`   | `localhost:9381`     | Admin server                  |

**Ports**: Container listens on 80 (HTTP) and 443 (HTTPS), mapped to host ports 8060 and 8443 respectively.

---

### RAGFlow Server (Python API)

**Entry point**: `api/ragflow_server.py`
**Framework**: Quart (async Flask)
**Internal port**: 9380 (also exposed to host)

**Startup sequence**:
1. Loads configuration from `service_conf.yaml`
2. Initializes database tables via Peewee ORM (`api/db/db_models.py`)
3. Seeds initial data (LLM factory definitions, system settings)
4. Loads plugins via `GlobalPluginManager`
5. Starts background `update_progress` thread for document processing status
6. Registers all Flask blueprints from `api/apps/`

**API Blueprints** (each is a `*_app.py` in `api/apps/`):

| Blueprint              | Prefix   | Purpose                                         |
|------------------------|----------|--------------------------------------------------|
| `kb_app`               | `/kb`    | Knowledge base CRUD, GraphRAG, RAPTOR            |
| `document_app`         | `/document` | Document upload, parsing, metadata            |
| `chunk_app`            | `/chunk` | Chunk retrieval and management                   |
| `dialog_app`           | `/dialog` | Chat/RAG application configuration              |
| `conversation_app`     | `/conversation` | Chat sessions, completions, SSE streaming |
| `canvas_app`           | `/canvas` | Agent workflow CRUD and execution               |
| `file_app`             | `/file`  | File storage (folders, upload, move)             |
| `file2document_app`    | `/file2document` | File-to-document mapping               |
| `user_app`             | `/user`  | Authentication, registration, profile            |
| `tenant_app`           | `/tenant` | Multi-tenant workspace management               |
| `llm_app`              | `/llm`   | LLM provider configuration                      |
| `tenant_llm_app`       | `/tenant_llm` | Per-tenant LLM settings                    |
| `api_app`              | `/api`   | API token management and stats                   |
| `system_app`           | `/system` | Global system settings                          |
| `connector_app`        | `/connector` | Data source connectors (Notion, Drive, etc.) |
| `search_app`           | `/search` | Search configuration and execution              |
| `evaluation_app`       | `/evaluation` | RAG evaluation/benchmarking                |
| `langfuse_app`         | `/langfuse` | Observability (Langfuse integration)          |
| `mcp_server_app`       | `/mcp_server` | MCP server management                      |
| `plugin_app`           | `/plugin` | Plugin/tool management                          |

**Connections to data stores**:
- **MySQL** — via Peewee ORM for all relational data (users, tenants, KBs, documents, tasks, conversations)
- **Elasticsearch/Infinity** — via `rag/utils/es_conn.py` or `infinity_conn.py` for document chunk indexing and retrieval
- **Redis** — session storage, distributed locks (for `update_progress`), synonym cache, task queues
- **MinIO** — document/file binary storage via `rag/utils/minio_conn.py`
- **TEI** — embedding requests via HTTP to `tei:80`

---

### Go Microservice (server_main)

**Entry point**: `cmd/server_main.go` → compiled binary `bin/server_main`
**Framework**: Gin (HTTP router)
**Purpose**: A high-performance Go backend that mirrors parts of the Python API for performance-critical operations.

**Internal structure** (`internal/`):

| Package      | Purpose                                              |
|--------------|------------------------------------------------------|
| `handler/`   | HTTP request handlers (KB, chat, document, chunk, file, LLM, user, tenant, connector, search) |
| `service/`   | Business logic layer                                  |
| `dao/`       | Data access objects (MySQL queries)                   |
| `model/`     | Type definitions and domain models                   |
| `engine/`    | Document engine abstraction (Elasticsearch + Infinity implementations) |
| `router/`    | Gin route registration                                |
| `cache/`     | In-memory caching                                     |
| `tokenizer/` | Token counting                                        |
| `nlp/`       | NLP utilities (tokenization, text processing)         |
| `logger/`    | Zap structured logging                                |

**Connections**: MySQL (via `dao/`), Elasticsearch/Infinity (via `engine/`).

---

### Task Executor

**Entry point**: `rag/svr/task_executor.py`
**Instances**: Configurable via `--workers=N` (default: 1)
**Purpose**: Background workers that process document ingestion tasks asynchronously.

**Processing pipeline per document**:
1. Picks tasks from the MySQL `task` table
2. Downloads the source file from MinIO
3. Selects the appropriate parser based on document type:
   - `naive` (generic), `pdf`, `docx`, `excel`, `ppt`, `html`, `markdown`, `email`, `audio`, `picture`, `paper`, `manual`, `book`, `resume`, `laws`, `table`, `qa`, `tag`
4. Delegates to `deepdoc/` for document parsing and layout analysis
5. Splits parsed content into chunks via `rag/flow/`
6. Generates embeddings (via TEI service or configured embedding model)
7. Optionally runs LLM extraction (metadata, keywords, Q&A, summaries)
8. Indexes chunks into Elasticsearch/Infinity with vectors
9. Updates task/document status in MySQL
10. Optionally runs RAPTOR (recursive abstractive summarization) or GraphRAG

**Connections**:
- **MySQL** — reads tasks, updates document/task status
- **MinIO** — downloads source files, stores parsed images/tables
- **Elasticsearch/Infinity** — indexes document chunks with embeddings
- **Redis** — heartbeat reporting, distributed coordination
- **TEI / External LLM** — embedding generation, LLM-based extraction

---

### Data Source Sync Worker

**Entry point**: `rag/svr/sync_data_source.py`
**Purpose**: Periodically synchronizes external data sources into RAGFlow knowledge bases.

**Supported data sources** (20+):
Notion, Discord, Google Drive, Moodle, Jira, Dropbox, Airtable, Asana, IMAP, Zendesk, SeaFile, RDBMS (SQL databases), WebDAV, Confluence, Gmail, Box, GitHub, GitLab, Bitbucket

**Sync mechanism**:
- Checkpoint-based incremental synchronization
- Creates new documents in MySQL for discovered items
- Queues parsing tasks for the Task Executor
- Batch indexing with configurable batch size

**Connections**: MySQL (connector/document tables), MinIO (file storage), external APIs.

---

### Admin Server

**Entry point**: `admin/server/admin_server.py`
**Framework**: Flask
**Internal port**: 9381
**Purpose**: System administration API with role-based access control.

**Features**: User management, service configuration, system monitoring, superuser initialization.

**Connections**: MySQL (admin data), shares auth with main API.

---

### MCP Server

**Entry point**: `mcp/server/server.py`
**Internal port**: 9382
**Purpose**: Exposes RAGFlow as a Model Context Protocol (MCP) tool provider, allowing external LLM clients to use RAGFlow's retrieval capabilities.

**Exposed tools**:
- `ragflow_retrieval` — search knowledge bases with dataset/document filtering

**Transport**: SSE (Server-Sent Events) and Streamable HTTP.

**Modes**: Self-hosted (within RAGFlow container) or external hosted mode with API key authorization.

---

### MySQL

**Image**: `mysql:8.0.39`
**Internal port**: 3306 (exposed to host as 5455)
**Purpose**: Primary relational database for all application state.

**Key tables** (28 total):

| Category           | Tables                                                        |
|--------------------|---------------------------------------------------------------|
| Identity           | `user`, `tenant`, `user_tenant`, `invitation_code`            |
| LLM config         | `llm_factories`, `llm`, `tenant_llm`                         |
| Knowledge base     | `knowledgebase`, `document`, `file`, `file2document`, `task`  |
| Chat               | `dialog`, `conversation`, `api_token`, `api_4_conversation`   |
| Agent/Canvas       | `user_canvas`, `canvas_template`, `user_canvas_version`       |
| Connectors         | `connector`, `connector2kb`, `sync_logs`                      |
| Evaluation         | `evaluation_dataset`, `evaluation_case`, `evaluation_run`, `evaluation_result` |
| System             | `system_settings`, `pipeline_operation_log`, `memory`, `mcp_server`, `search`, `tenant_langfuse` |

**ORM**: Peewee (Python), raw SQL via `dao/` (Go).

**Data relationships**:
```
user ──1:N──▶ user_tenant ◀──N:1── tenant
tenant ──1:N──▶ knowledgebase ──1:N──▶ document ──1:N──▶ task
tenant ──1:N──▶ tenant_llm ──N:1──▶ llm_factories
tenant ──1:N──▶ dialog ──1:N──▶ conversation
tenant ──1:N──▶ user_canvas
file ──M:N──▶ file2document ◀──M:N── document
connector ──M:N──▶ connector2kb ◀──M:N── knowledgebase
```

---

### Document Engine

RAGFlow supports multiple document/vector search engines, selected via the `DOC_ENGINE` environment variable. Only one runs at a time.

#### Elasticsearch (default)

**Image**: `elasticsearch:8.11.3`
**Internal port**: 9200 (exposed to host as 1200)
**Purpose**: Full-text search + dense vector storage for document chunks.

**Indices**: One index per knowledge base, storing chunk text, metadata, and embedding vectors.

**Connection**: REST API via `rag/utils/es_conn.py` and `internal/engine/elasticsearch/`.

#### OpenSearch

**Image**: `opensearchproject/opensearch:2.19.1`
**Internal port**: 9201 (exposed to host as 1201)
**Purpose**: Drop-in alternative to Elasticsearch with same capabilities.

#### Infinity

**Image**: `infiniflow/infinity:v0.7.0-dev2`
**Ports**: 23817 (Thrift), 23820 (HTTP), 5432 (PostgreSQL wire protocol)
**Purpose**: High-performance vector database with hybrid search (dense + sparse vectors).

**Connection**: Via `rag/utils/infinity_conn.py` using Thrift protocol.

#### OceanBase

**Image**: `oceanbase/oceanbase-ce:4.4.1.0`
**Port**: 2881
**Purpose**: Distributed relational + vector database.

#### SeekDB

**Image**: `oceanbase/seekdb:latest`
**Port**: 2881
**Purpose**: Lightweight version of OceanBase for smaller deployments.

---

### MinIO (Object Storage)

**Image**: `quay.io/minio/minio`
**Ports**: 9000 (API), 9001 (Console)
**Purpose**: S3-compatible object storage for all binary file data.

**Stored data**:
- Uploaded source documents (PDF, DOCX, images, etc.)
- Parsed document artifacts (extracted images, tables)
- Generated thumbnails

**Connection**: Via `rag/utils/minio_conn.py` using the MinIO Python SDK.

**Alternatives** (configurable in `service_conf.yaml`): AWS S3, Alibaba OSS, Azure Blob, Google Cloud Storage, OpenDAL.

---

### Redis (Valkey)

**Image**: `valkey/valkey:8`
**Internal port**: 6379 (exposed to host as 16379)
**Purpose**: In-memory data store for caching, coordination, and real-time features.

**Usage**:
- **Session storage** — Quart session backend
- **Distributed locks** — `update_progress` thread uses Redis locks to avoid conflicts across instances
- **Task executor heartbeats** — workers report status to Redis
- **Synonym cache** — real-time synonym lookup for query expansion
- **Term frequency data** — cached TF-IDF weights

**Configuration**: Database index 1, 128MB max memory with LRU eviction.

---

### TEI (Text Embeddings Inference)

**Image**: `infiniflow/text-embeddings-inference` (CPU or GPU variant)
**Internal port**: 80 (exposed to host as 6380)
**Purpose**: High-performance embedding model server for vectorizing text chunks and queries.

**Default model**: `Qwen/Qwen3-Embedding-0.6B` (configurable to `BAAI/bge-m3`, `BAAI/bge-small-en-v1.5`, etc.)

**Connection**: HTTP REST API. The RAGFlow server and task executors call `http://tei:80` for embedding generation.

**Profiles**: `tei-cpu` (CPU inference) or `tei-gpu` (GPU inference with NVIDIA CUDA).

---

### Sandbox Executor Manager

**Image**: `infiniflow/sandbox-executor-manager:latest`
**Port**: 9385
**Profile**: `sandbox` (opt-in)
**Purpose**: Secure code execution environment for agent workflows that run user-provided code.

**Features**:
- Manages a pool of isolated Docker containers
- Supports Python and Node.js execution environments
- Memory limits, timeouts, and seccomp security profiles
- Requires Docker socket mount for container management

**Base images**: `infiniflow/sandbox-base-python:latest`, `infiniflow/sandbox-base-nodejs:latest`

---

### Kibana (Optional)

**Image**: `kibana:${STACK_VERSION}`
**Port**: 5601 (exposed as 6601)
**Profile**: `kibana` (opt-in)
**Purpose**: Elasticsearch monitoring and debugging dashboard.

---

## Internal Subsystems

### RAG Core

Located in `rag/`, this is the retrieval-augmented generation engine.

| Subpackage        | Purpose                                                    |
|-------------------|------------------------------------------------------------|
| `rag/app/`        | Document-type-specific chunking (20+ formats: PDF, DOCX, Excel, PPT, HTML, Markdown, email, audio, images, academic papers, legal docs, resumes, books, manuals, Q&A) |
| `rag/flow/`       | Processing pipeline framework: `Pipeline`, `Parser`, `Splitter`, `Extractor` components with configurable token sizing and overlap |
| `rag/nlp/`        | NLP components: `FulltextQueryer` (hybrid search with term weighting), `rag_tokenizer` (multi-language), `term_weight` (TF-IDF), `synonym` (Redis-backed) |
| `rag/graphrag/`   | Knowledge graph RAG: entity extraction, resolution, relationship mapping, graph-based retrieval |
| `rag/raptor.py`   | RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval — hierarchical document summarization using UMAP + GMM clustering |
| `rag/svr/`        | Background services: `task_executor.py`, `sync_data_source.py`, `cache_file_svr.py` |
| `rag/utils/`      | Storage connectors: Elasticsearch, Infinity, Redis, MinIO, S3, GCS, OSS, Azure, OceanBase, OpenDAL, Tavily |

### Deep Document Understanding

Located in `deepdoc/`, this subsystem handles raw document parsing and visual analysis.

**Parsers** (`deepdoc/parser/`):

| Parser               | Formats                          | Technique                          |
|----------------------|----------------------------------|------------------------------------|
| `RAGFlowPdfParser`   | PDF                              | Layout analysis + OCR + XGBoost concat detection |
| `PaddleOCRParser`    | PDF, images                      | PaddleOCR v3/v4 with layout recognition |
| `MinerUParser`       | PDF                              | MinerU server/pipeline             |
| `DoclingParser`      | PDF                              | Docling library                    |
| `TCADPParser`        | PDF                              | Tsinghua TCADP                     |
| `RAGFlowDocxParser`  | DOCX                             | Python-docx extraction             |
| `RAGFlowExcelParser` | XLS, XLSX                        | Spreadsheet parsing                |
| `RAGFlowPptParser`   | PPT, PPTX                        | Slide content extraction           |
| `RAGFlowHtmlParser`  | HTML                             | Web content parsing                |
| `RAGFlowMarkdownParser` | Markdown                      | Heading-aware hierarchy            |
| `RAGFlowJsonParser`  | JSON                             | Structured data extraction         |
| `RAGFlowTxtParser`   | Plain text                       | Delimiter-based splitting          |

**Vision models** (`deepdoc/vision/`):
- `OCR` — Multi-language OCR with PaddleOCR and orientation classification
- `LayoutRecognizer` — ONNX-based document layout detection (headings, paragraphs, tables, figures)
- `TableStructureRecognizer` — Table cell/row/column detection
- Supports Ascend NPU acceleration alongside CUDA GPUs

### Agent / Canvas Workflow Engine

Located in `agent/`, this provides a visual workflow (canvas) system for building agentic RAG applications.

**Canvas engine** (`agent/canvas.py`):
- JSON/dict DSL defines workflows as directed graphs
- `Graph` class manages component lifecycle, message passing, and async execution
- Redis-backed logging and progress tracking
- Task cancellation support

**Components** (`agent/component/`):

| Category       | Components                                                  |
|----------------|-------------------------------------------------------------|
| Control flow   | `Begin`, `ExitLoop`, `Message`, `Switch`, `Iteration`, `Loop` |
| Processing     | `LLM` (LLM invocation), `Invoke` (sub-workflows), `AgentWithTools` (tool-calling loop) |
| Data ops       | `VariableAssigner`, `VariableAggregator`, `DataOperations`, `ListOperations`, `StringTransform`, `Categorize`, `ExcelProcessor` |
| Generation     | `FillUp` (template filling), `DocsGenerator` (document generation) |

**Tools** (`agent/tools/`): 15+ integrations — knowledge base retrieval, web search (Tavily, DuckDuckGo, SearXNG, Google), code execution, SQL, web crawling, email, ArXiv, GitHub, Google Scholar, PubMed, Wikipedia, Yahoo Finance, DeepL translation, weather API, Chinese financial data (WenCai, TuShare, Jin10, AKShare).

**Templates** (`agent/templates/`): 25+ pre-built workflows — web search assistant, deep research, SEO blog generation, customer review analysis, CV analysis, SQL assistant, trip planner, knowledge base Q&A, and more.

### LLM Abstraction Layer

Located in `rag/llm/`, this provides a unified interface to 50+ LLM providers.

| Model Type       | File                    | Providers                                                  |
|------------------|-------------------------|------------------------------------------------------------|
| Chat             | `chat_model.py`         | OpenAI, Azure, Anthropic, Ollama, DeepSeek, Gemini, xAI, Groq, Bedrock, Mistral, Tongyi-Qianwen, ZHIPU-AI, MiniMax, and 35+ more |
| Embedding        | `embedding_model.py`    | TEI (default), OpenAI, Azure, BaiChuan, Tongyi, ZHIPU, Ollama, Xinference, HuggingFace, and more |
| Reranking        | `rerank_model.py`       | Jina, Xinference, and others                               |
| Vision           | `cv_model.py`           | OpenAI, Azure, Gemini, Claude (image understanding)        |
| OCR              | `ocr_model.py`          | MinerU, PaddleOCR                                          |
| Text-to-Speech   | `tts_model.py`          | Fish Audio, FishTTS                                        |
| Speech-to-Text   | `sequence2txt_model.py` | Whisper and various providers                              |

### Python SDK

Located in `sdk/python/ragflow_sdk/`, provides programmatic access to the RAGFlow API.

**Main classes**: `RAGFlow` (client), `DataSet`, `Document`, `Chunk`, `Chat`, `Session`, `Agent`, `Memory`.

---

## Data Flow Diagrams

### Document Ingestion Pipeline

```
User uploads file
       │
       ▼
  ┌──────────┐    binary file    ┌───────┐
  │ Nginx    │ ──────────────▶   │ MinIO │
  │ :80      │                   └───────┘
  └────┬─────┘                       ▲
       │ /api/v1/document/upload     │ download for parsing
       ▼                             │
  ┌──────────────┐  create task  ┌───┴────────────┐
  │ Python API   │ ────────────▶ │    MySQL       │
  │ :9380        │  (task table) │ (document,task)│
  └──────────────┘               └───┬────────────┘
                                     │ poll tasks
                                     ▼
                              ┌──────────────────┐
                              │  Task Executor   │
                              │  (rag/svr/)      │
                              └──────┬───────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                 ▼
             ┌───────────┐   ┌────────────┐   ┌────────────┐
             │ deepdoc/  │   │ rag/app/   │   │ rag/flow/  │
             │ parser +  │   │ doc-type   │   │ splitter + │
             │ vision    │   │ chunking   │   │ pipeline   │
             └─────┬─────┘   └─────┬──────┘   └─────┬──────┘
                   │               │                 │
                   └───────────────┴─────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼               ▼
             ┌───────────┐  ┌──────────┐   ┌────────────────┐
             │   TEI     │  │  MinIO   │   │ Elasticsearch  │
             │ (embed)   │  │ (images) │   │ (index chunks) │
             └───────────┘  └──────────┘   └────────────────┘
```

### Query / Chat Pipeline

```
User sends question
       │
       ▼
  ┌──────────┐
  │ Nginx    │
  │ :80      │
  └────┬─────┘
       │ /api/v1/conversation/completion
       ▼
  ┌──────────────┐
  │ Python API   │
  │ :9380        │
  └──────┬───────┘
         │
         ├──1. Load dialog config ──────────▶ MySQL (dialog, tenant_llm)
         │
         ├──2. Query preprocessing
         │     ├── Tokenization (rag/nlp/rag_tokenizer)
         │     ├── Term weighting (rag/nlp/term_weight)
         │     └── Synonym expansion (rag/nlp/synonym → Redis)
         │
         ├──3. Generate query embedding ────▶ TEI (:80)
         │
         ├──4. Hybrid retrieval ────────────▶ Elasticsearch / Infinity
         │     (full-text BM25 + vector kNN)   (knowledge base indices)
         │
         ├──5. Rerank results ──────────────▶ Rerank model (configured LLM)
         │
         ├──6. Build prompt with context
         │
         └──7. LLM generation (streaming) ─▶ Configured LLM provider
                                               (OpenAI, DeepSeek, etc.)
         │
         ▼
  SSE stream back to client
```

### Agent Canvas Execution

```
User triggers canvas
       │
       ▼
  ┌──────────────┐
  │ Python API   │──── Load canvas DSL ──▶ MySQL (user_canvas)
  │ /canvas/     │
  └──────┬───────┘
         │
         ▼
  ┌──────────────────────────────┐
  │   Canvas Engine (Graph)      │
  │   agent/canvas.py            │
  └──────┬───────────────────────┘
         │
         │  Execute component graph:
         │
         │  Begin ──▶ LLM ──▶ Retrieval ──▶ Switch ──▶ ...
         │              │         │              │
         │              ▼         ▼              ▼
         │         LLM API    ES/Infinity    Conditional
         │                                   branching
         │
         │  Tool calls along the way:
         │  ├── Web search (Tavily, DuckDuckGo)
         │  ├── Code execution → Sandbox Manager (:9385)
         │  ├── SQL execution → External DB
         │  ├── KB retrieval → Elasticsearch
         │  └── External APIs (ArXiv, GitHub, etc.)
         │
         ▼
  Stream results via SSE
```

---

## Network and Port Map

All services communicate over the Docker bridge network `ragflow`. Below are the internal (container-to-container) and external (host-exposed) ports.

| Service              | Internal Port | Host Port  | Protocol | Purpose                  |
|----------------------|---------------|------------|----------|--------------------------|
| Nginx                | 80            | 8060       | HTTP     | Web UI                   |
| Nginx                | 443           | 8443       | HTTPS    | Web UI (TLS)             |
| RAGFlow API          | 9380          | 9380       | HTTP     | REST API                 |
| Admin Server         | 9381          | 9381       | HTTP     | Admin API                |
| MCP Server           | 9382          | 9382       | HTTP/SSE | MCP protocol             |
| MySQL                | 3306          | 5455       | MySQL    | Relational database      |
| Elasticsearch        | 9200          | 1200       | HTTP     | Search/vector engine     |
| OpenSearch           | 9201          | 1201       | HTTP     | Search/vector engine     |
| Infinity (Thrift)    | 23817         | 23817      | Thrift   | Vector DB                |
| Infinity (HTTP)      | 23820         | 23820      | HTTP     | Vector DB API            |
| Infinity (PSQL)      | 5432          | 5432       | PostgreSQL | Vector DB SQL          |
| OceanBase            | 2881          | 2881       | MySQL    | Distributed DB           |
| SeekDB               | 2881          | 2881       | MySQL    | Lightweight DB           |
| MinIO API            | 9000          | 9000       | HTTP     | Object storage API       |
| MinIO Console        | 9001          | 9001       | HTTP     | Object storage UI        |
| Redis (Valkey)       | 6379          | 16379      | Redis    | Cache/locks/sessions     |
| TEI                  | 80            | 6380       | HTTP     | Embedding service        |
| Kibana               | 5601          | 6601       | HTTP     | ES monitoring            |
| Sandbox Manager      | 9385          | 9385       | HTTP     | Code execution           |

---

## Configuration Files

| File                                  | Purpose                                                    |
|---------------------------------------|------------------------------------------------------------|
| `docker/.env`                         | Master environment variables (ports, passwords, device, profiles, images) |
| `docker/service_conf.yaml.template`   | Backend service connection config (MySQL, MinIO, ES, Redis, TEI, etc.) — env vars are substituted at container startup |
| `docker/docker-compose.yml`           | Main compose: RAGFlow container (cpu/gpu variants) with ports, volumes, GPU reservations |
| `docker/docker-compose-base.yml`      | Infrastructure services: doc engines, MySQL, MinIO, Redis, TEI, Kibana, Sandbox |
| `docker/nginx/ragflow.conf`           | Nginx reverse proxy routing rules                          |
| `docker/nginx/nginx.conf`             | Nginx global config (worker processes, client body size)   |
| `docker/nginx/proxy.conf`             | Proxy header forwarding (WebSocket upgrade, timeouts)      |
| `docker/entrypoint.sh`               | Container entrypoint: waits for MySQL, generates config, launches all processes |
| `docker/launch_backend_service.sh`    | Starts task executors and API server with jemalloc and retry logic |
| `docker/init.sql`                     | MySQL initialization script (creates database, grants)     |
| `conf/service_conf.yaml`             | Local development service config (same format as template) |
| `conf/mapping.json`                  | Elasticsearch index mapping for document chunks            |
| `conf/llm_factories.json`            | Seed data for supported LLM providers and their models     |
