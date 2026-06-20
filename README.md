## deployment link https://user719-blip.github.io/endee_frontend/ 

** backend is down due to inactivity(unpaid tier) **

# Codebase QA App

Flutter web app for codebase upload + RAG chat with enriched chunking and intelligent fallback retrieval.

## Quick Start

### 1. Configure Supabase Credentials

Get your credentials from [Supabase Dashboard](https://supabase.com) → Settings → API:
- Copy **Project URL** → `SUPABASE_URL`
- Copy **anon (public) key** → `SUPABASE_ANON_KEY`

Run Flutter with credentials:

**PowerShell (Windows):**
```powershell
.\run_with_supabase.ps1 -supabaseUrl "https://your-project.supabase.co" -supabaseAnonKey "sb_publishable_..."
```

**Bash/Shell (macOS/Linux):**
```bash
./run_with_supabase.sh "https://your-project.supabase.co" "sb_publishable_..."
```

Or use the batch file (Windows):
```powershell
.\run_with_supabase.cmd
```

### 2. Start Backend

```bash
cd backend
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

### 3. Upload Code & Ask Questions

1. Launch Flutter app
2. Select a `.py` file or `.zip` archive
3. Ask specific questions (high similarity) or generic ones (uses fallback + preamble)

For detailed setup, see [ENRICHED_CHUNKING_SETUP.md](ENRICHED_CHUNKING_SETUP.md) and [QUICK_REFERENCE.md](QUICK_REFERENCE.md).

---

## High-Level Design

```mermaid
flowchart LR
  U[User Browser] --> F[Flutter Web Frontend]
  F --> B[FastAPI Backend on Render]
  B --> S[Supabase Functions\nembed + answer]
  B --> E[Endee Vector Index]
  S --> B
  E --> B
  B --> F
```

## Low Level Design

see `frontend_LLD_CLASS_DIAGRAM.md`
and for flow see `flow.md`


## Deployment Split (Two Repos)

1. Frontend repo:
	- Include Flutter project files needed for web.
	- Exclude backend folder if splitting from monorepo.
	- Used github actions workflow to build on push to GitHub Pages. Check `.github/workflow`
2. Backend repo:
	- Include only `backend/` content.
	- Deploy with Render using `uvicorn main:app --host 0.0.0.0 --port $PORT`.

Detailed split checklist and env vars:

- `DEPLOYMENT_CHECKLIST.md`

## Supabase Edge Functions (What They Do)

- `embed` function:
  - Receives plain text from backend.
  - Calls Hugging Face embedding model (`BAAI/bge-small-en-v1.5`).
  - Returns numeric embedding vector.
  - Used by backend during ingest and query embedding.
- `answer` function:
  - Receives retrieved context + user question.
  - Calls Hugging Face chat/generation models to produce final answer.
  - Supports streaming responses for token-by-token UI updates.
  - Returns fallback context-grounded answer if generation providers fail.

## Runtime Constraints

- Retrieval chunk count is fixed at `top_k = 3`
- Question length must be less than `100 words` 
- Session cache holds max `200 chunks` per session
- Session data expires after `1800 seconds` (30 minutes) of inactivity
- Generic queries intentionally return `0.0` similarity when using fallback cache
- Fallback chunks are local copies, not re-embedded (fast retrieval)

## Extra Flow Docs & Guides

- Frontend flow: `flow.md`
- Backend flow: `backend/flow.md`
- **Setup guide**: `ENRICHED_CHUNKING_SETUP.md` (detailed Supabase config, enrichment, generic queries)
- **Quick reference**: `QUICK_REFERENCE.md` (quick start, checklists, debug commands)

## What This App Is

This project is a codebase question-answering application built for uploading source files or zipped repositories, indexing them for semantic search, and then letting users ask natural-language questions about the uploaded code.

At a practical level, the app helps a user:

- upload a single source file or a full `.zip` codebase
- split code into searchable chunks
- generate embeddings for those chunks
- store the vectors in Endee
- retrieve the most relevant chunks for a question
- generate a final answer grounded in the retrieved code context

The frontend is a Flutter web UI, while the backend is a FastAPI service that handles ingestion, chunking, vector storage, session isolation, and retrieval.

## What The App Does

The app supports a simple RAG flow for code understanding:

1. A user uploads a file or a zip archive from the browser.
2. The Flutter frontend sends the upload to the Python backend.
3. The backend reads supported source/config files and chunks them into logical units.
4. Each chunk is embedded through the Supabase `embed` function.
5. The backend stores each embedding in Endee together with metadata like file path, symbol name, line numbers, chunk type, and session id.
6. When the user asks a question, the backend embeds the question and searches Endee for the top 3 matching chunks.
7. The frontend combines retrieved snippets with session memory and sends that context to the Supabase `answer` function.
8. The final answer is streamed back into the UI so the user sees it appear live.

This makes the app useful for:

- understanding unfamiliar codebases
- locating where business logic lives
- answering architecture or implementation questions
- inspecting classes, functions, imports, and support files
- keeping temporary session-scoped code context without mixing different uploads

## Main Features

- Upload a single source file directly from the browser
- Upload a `.zip` archive containing a larger codebase
- Automatic chunking for Python, JavaScript, TypeScript, Java, Go, C/C++, C#, Ruby, PHP, Swift, JSON, YAML, XML, TOML, Gradle, and other support files
- Session-based indexing so one upload session stays isolated from another
- Semantic retrieval with a fixed `top_k = 3`
- Live streamed answer generation in the UI
- Session memory in the frontend for follow-up questions
- Reset flow that deletes stored vectors for the active session
- TTL-based cleanup of expired backend sessions

## New Features: Enriched Chunking & Smart Fallbacks

### Enriched Chunking

Chunks are automatically enhanced with metadata during ingestion:

- **Filename**: Shows which file the code is from
- **Class/Function Name**: Identifies the symbol
- **Function Signature**: Captures the function definition line
- **Line Numbers**: Indicates code location in the file
- **Language Hint**: Shows programming language context

This metadata helps with retrieval quality and provides better context for generic queries.

### Generic Query Handling

The system automatically detects generic or ambiguous queries like:
- "what does this code do?"
- "explain this code"
- "give me a summary"
- "how does this work?"
- "what is this?"

For generic queries:
1. **Smart Preamble**: "I found X relevant code segments from auth.py including login_user, logout_user..."
2. **Session Fallback**: Falls back to cached chunks if semantic search returns no results
3. **Cached Answers**: Provides template responses for common patterns

### Session-Based Fallback & Caching

When semantic search finds no results:
- Backend automatically uses locally cached chunks from the current session
- Cache stores up to 200 chunks per session with 30-minute TTL
- Fallback chunks are returned with `similarity = 0.0` to distinguish from true semantic hits
- This enables "what does code do?" queries to still provide relevant context

### Query Processing Flow

```
Question
    ↓
Embed (Supabase)
    ↓
Semantic Search
    ├─ Found? → Use with high similarity (80%+)
    └─ Not found? → Use session cache with preamble
    ↓
Detect if generic?
    ├─ Yes → Add smart preamble ("I found X chunks...")
    └─ No → Return context as-is
    ↓
Send to LLM (Supabase)
    ↓
Stream answer to UI
```


## Tech Stack Used

### Frontend

- Flutter Web
- Dart
- `http` package for backend and Supabase requests
- `file_picker` for selecting local source files and zip archives
- Material 3 UI

### Backend

- FastAPI
- Uvicorn
- `python-multipart` for file uploads
- custom chunking logic for different code and support file types

### Retrieval And AI Layer

- Endee for vector indexing and similarity search
- Supabase Edge Functions as the bridge for embedding and answer generation
- Hugging Face embedding model: `BAAI/bge-small-en-v1.5`
- Hugging Face generation/chat models behind the `answer` function

## How Endee Is Used To Retrieve Data

Endee is the vector database layer of this app. It is used after the backend converts code chunks into embeddings.

### During ingest

When a file or zip is uploaded:

- the backend chunks the file into meaningful pieces such as imports, functions, classes, support files, or fallback line blocks
- each chunk is converted into a richer embedding input that includes:
  - session id
  - file path
  - language
  - chunk type
  - symbol name
  - line numbers
  - raw chunk text
- that text is sent to the Supabase `embed` function
- the returned embedding vector is upserted into Endee

Each Endee record stores:

- a unique vector id
- the vector itself
- metadata containing the original chunk details and text

This metadata is important because retrieval does not return only similarity scores; it also returns the original file/snippet information needed to explain the answer in context.

### During query

When the user asks a question:

- the question is embedded using the same embedding pipeline
- the backend queries the existing Endee index
- the search is filtered by `session_id` so only vectors from the current upload session are searched
- the backend oversamples results internally and then deduplicates them
- the final response returns the top 3 relevant chunks plus a combined text context

The retrieved chunk metadata includes items like:

- file path
- symbol name
- line range
- chunk type
- snippet text

That retrieved context is then sent to the `answer` function so the generated answer stays grounded in the uploaded code.

### Session isolation and cleanup

Endee is also part of the session lifecycle:

- every stored vector is tagged with a `session_id`
- vector ids are tracked locally in a session manifest
- resetting a session deletes that session's vectors from Endee
- expired sessions can be cleaned automatically using TTL logic

This prevents different uploads from polluting each other and keeps temporary code indexing manageable.

## How Chunking Works

The backend does not store entire codebases as one big blob. It first breaks files into smaller retrievable units.

- Python files are parsed with `ast` and split into imports, classes, and functions when possible
- Braced languages use pattern-based extraction for classes and functions
- Support files like `package.json`, `requirements.txt`, `pom.xml`, `go.mod`, and similar files are stored as support-file chunks
- Files that cannot be parsed structurally fall back to line-based chunking

This chunking strategy improves retrieval quality because the embedding usually represents a smaller, more meaningful unit of code.

## Frontend And Backend Responsibilities

### Flutter frontend

The frontend is responsible for:

- letting the user upload files or zip archives
- creating a new session id
- calling the FastAPI backend for ingest, query, and reset operations
- showing retrieved chunks
- maintaining lightweight conversation memory for follow-up questions
- streaming generated answers into the interface

### FastAPI backend

The backend is responsible for:

- validating uploads and questions
- extracting source files from zip archives
- identifying supported code/config files
- chunking source content
- generating embeddings through Supabase
- creating or loading the Endee index
- storing and searching vectors
- filtering data by session id
- deleting vectors during reset or TTL cleanup

## Important Runtime Behavior

- Retrieval is fixed to top 3 chunks
- Questions must be under 100 words
- The Endee index is created automatically on first successful write
- If no vectors exist yet, querying will fail until at least one file or zip has been ingested
- Answer generation is separate from retrieval: Endee retrieves context, Supabase generates the final response
- If answer generation fails, the UI still shows retrieved chunks so the user can inspect the relevant code manually

## Backend Endpoints

The main backend endpoints are:

- `GET /health` for a simple health check
- `POST /ingest/file` to upload and index one file
- `POST /ingest/zip` to upload and index a zip archive
- `POST /store` to manually store a vector payload
- `POST /search` to search using a provided vector
- `POST /query` to embed a question and retrieve the top matching chunks
- `POST /session/reset` to delete vectors for one session

## Configuration Notes

Important environment/config values used by the project include:

### Backend Environment Variables

- `ENDEE_TOKEN` - Token for Endee vector database access
- `ENDEE_INDEX_NAME` - Name of the Endee index (default: "codebase")
- `ENDEE_INDEX_SPACE_TYPE` - Distance metric for embeddings (default: "cosine")
- `ENDEE_INDEX_PRECISION` - Precision level for vectors (default: "INT8")
- `SUPABASE_URL` - URL of your Supabase project
- `SUPABASE_ANON_KEY` - Public anon key from Supabase
- `SUPABASE_EMBED_FUNCTION` - Name of embed function (default: "embed")
- `SESSION_TTL_SECONDS` - Session expiry time in seconds (default: 1800)
- `MAX_FALLBACK_LINES` - Max lines per fallback chunk (default: 120)

### Frontend Dart Defines (--dart-define)

Pass these when running Flutter:

```bash
--dart-define SUPABASE_URL="https://your-project.supabase.co"
--dart-define SUPABASE_ANON_KEY="sb_publishable_..."
--dart-define PY_BACKEND_URL="http://127.0.0.1:8000"
```

Or use the launcher scripts (`run_with_supabase.ps1`, `run_with_supabase.sh`, `run_with_supabase.cmd`) which inject these automatically.

### Generic Query Detection

Backend uses regex patterns to detect generic queries:

- `what\s+does\s+(?:this\s+)?code\s+do` → "what does code do"
- `explain\s+(?:this\s+)?code` → "explain this code"
- Queries with ≤2 words also detected as generic
- Results in smart preamble + session fallback behavior

### Cached Answers

Fallback responses for common patterns:

- **Generic queries**: "I found X relevant code segments from..."
- **Empty results**: "No matching code segments found. Try asking about specific function/class names..."

## Why This Architecture Matters

This app separates retrieval from answer generation in a clean way:

- Flutter provides the user-facing upload and chat experience
- FastAPI handles code-aware ingestion and retrieval orchestration
- Supabase functions centralize embedding and LLM response generation
- Endee stores vectors and returns the most semantically relevant code chunks

That separation makes the system easier to deploy, extend, and debug. It also keeps the retrieval layer reusable even if the answer-generation model changes later.

## Troubleshooting

### "Missing SUPABASE_URL or SUPABASE_ANON_KEY"

**Cause**: Flutter app launched without `--dart-define` credentials

**Fix**:
- Use one of the launcher scripts: `.\run_with_supabase.ps1`, `.\run_with_supabase.sh`, or `.\run_with_supabase.cmd`
- Or pass credentials manually: 
  ```bash
  flutter run --dart-define SUPABASE_URL="..." --dart-define SUPABASE_ANON_KEY="..." -d chrome
  ```

### Generic Queries Return 0.0 Similarity

**Cause**: Expected behavior for generic query fallback

**Fix**: This is intentional. Generic queries like "what does code do" use session cache with 0.0 similarity. The system compensates with:
- Smart preamble showing which files/symbols were found
- Full context retrieved from session cache
- This allows answers even when semantic match is low

### High Similarity Score Drops Unexpectedly

**Cause**: Enrichment metadata was interfering with embeddings

**Status**: ✅ Fixed in latest version. Embeddings now use raw code text only (no metadata prefixes)

**What to do**:
1. Backend should auto-reload if using `--reload`
2. Re-ingest your files (clear old vectors first)
3. Specific queries should show 80%+ similarity again

### Session Cache Empty After Upload

**Cause**: Cache expires after `SESSION_TTL_SECONDS` (default 30 minutes) or server restarted

**Fix**:
- Re-upload the file to repopulate cache
- Check `.session_chunk_cache.json` in backend folder
- Ensure `SESSION_TTL_SECONDS` env var is set appropriately

### No Chunks Found After Successful Upload

**Cause**: Backend query result parsing issue or session filtering too strict

**Debug**:
- Check backend logs for: `query session=... retrieved=X`
- If `retrieved=0`, check if chunks were stored: `.session_manifest.json`
- Verify session_id matches between frontend and backend

### Flutter App Freezes on Query

**Cause**: SSE stream parsing issue or Supabase function timeout

**Debug**:
- Check browser console for errors
- Check backend logs for Supabase function failures
- Verify `SUPABASE_ANON_KEY` has correct permissions

### Answer Generation Fails Silently

**Status**: ✅ Fixed in latest version. Errors now show in UI with fallback answer

**What happens now**:
- Chat turn is added to conversation even on error
- Latest answer is displayed showing error message
- Status bar shows "answer generation failed"
- User can still see retrieved chunks
