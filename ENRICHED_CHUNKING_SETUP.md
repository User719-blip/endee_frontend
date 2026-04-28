# Enriched Chunking & Supabase Configuration Guide

## Supabase Credentials Setup

### Option 1: Direct Command (Quick Start)
Run the Flutter app with Supabase credentials directly:

```bash
# PowerShell (Windows)
.\run_with_supabase.ps1 -supabaseUrl "https://your-project.supabase.co" -supabaseAnonKey "eyJ..." -device chrome

# Bash/Shell (macOS/Linux)
./run_with_supabase.sh "https://your-project.supabase.co" "eyJ..." "http://127.0.0.1:8000" chrome
```

### Option 2: Using .env File
1. Copy the template to create a local env file:
   ```bash
   cp .env.flutter .env.flutter.local
   ```

2. Edit `.env.flutter.local` with your actual credentials:
   ```
   export SUPABASE_URL="https://your-project-ref.supabase.co"
   export SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...."
   export PY_BACKEND_URL="http://127.0.0.1:8000"
   ```

3. Load the env file and run:
   ```bash
   source .env.flutter.local && ./run_with_supabase.sh
   ```

### Finding Your Supabase Credentials
1. Go to your **Supabase Dashboard**
2. Navigate to **Settings → API**
3. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon (public) key** → `SUPABASE_ANON_KEY`

⚠️ **Important**: Never commit `.env.flutter.local` to git. Add it to `.gitignore`.

---

## Enriched Chunking Features

### What is Enriched Chunking?
Enriched chunking automatically injects metadata into code chunks during ingestion:
- **Filename**: Shows which file the code is from
- **Class/Function Name**: Identifies the symbol
- **Function Signature**: Captures the function definition
- **Line Numbers**: Indicates code location
- **Language Hint**: Shows programming language context

### Example
**Original chunk:**
```python
def clean_dataframe(df):
    df.dropna(inplace=True)
    return df
```

**Enriched (used for embeddings):**
```
File: data_utils.py
Function: clean_dataframe
Signature: def clean_dataframe(df):

def clean_dataframe(df):
    df.dropna(inplace=True)
    return df
```

### How It Helps
1. **Better Semantic Search**: Embeddings now include context like "File: auth.py" + the code
2. **Improved Generic Queries**: When you ask "what does code do", metadata helps find relevant functions
3. **Smarter Fallbacks**: Session fallback chunks include rich context

---

## Generic Query Handling

### Detection
The system automatically detects generic queries like:
- "what does this code do"
- "explain this code"  
- "give me a summary"
- "how does this work"
- "what is this"

### Response Enhancement
For generic queries with retrieved chunks, the backend provides:
1. **Smart Preamble**: "I found X relevant code segments from auth.py including login_user, logout_user..."
2. **Enriched Context**: Full chunk text with metadata prefix
3. **Cached Answers**: Fallback responses if semantic search fails

### Example Flow
```
User asks: "what does this code do?"
↓
System detects: Generic query
↓
Retrieves: Multiple relevant chunks with enriched context
↓
Returns: Preamble + full context with metadata
↓
UI shows: Clear answer with code examples and metadata
```

---

## Cached Answers

The system includes cached response templates for common scenarios:

| Scenario | Response Template |
|----------|------------------|
| **Generic Query** | "Based on the code analysis, the retrieved chunks show the relevant implementation..." |
| **Empty Results** | "No matching code segments found. Try asking about specific function/class names..." |

These are used as fallbacks when:
- Supabase functions are unavailable
- Query returns no results  
- Generic queries get low similarity scores

---

## Query Processing Flow

```
1. User Question
    ↓
2. Embed Question (Supabase)
    ↓
3. Search by Similarity
    ├─ Semantic search in Endee index
    ├─ Filter by session
    └─ Fallback to session cache if empty
    ↓
4. Enrich Results
    ├─ Extract text & metadata
    ├─ Normalize similarity scores
    └─ Detect if generic query
    ↓
5. Add Context
    ├─ If generic: Add smart preamble
    ├─ If empty: Provide cached answer
    └─ Build context string
    ↓
6. Return Response
    ├─ Backend context (for LLM)
    ├─ Retrieved chunks (for UI)
    ├─ Best similarity score
    └─ is_generic_query flag
    ↓
7. Generate Answer (Supabase/Mistral)
    ├─ Use backend context
    ├─ Include generic query context if applicable
    └─ Stream tokens to UI
```

---

## Configuration Constants

Located in `backend/main.py`:

```python
GENERIC_QUERY_PATTERNS = {
    r"what\s+does\s+(?:this\s+)?code\s+do": "...",
    r"explain\s+(?:this\s+)?code": "...",
    # ... more patterns
}

CACHED_ANSWERS = {
    "generic": "Based on the code analysis...",
    "empty_result": "No matching code segments...",
}

FIXED_TOP_K = 3              # Results to retrieve
MAX_QUESTION_WORDS = 99      # Max question length
SESSION_TTL_SECONDS = 1800   # 30 minutes
```

---

## Troubleshooting

### "Missing SUPABASE_URL or SUPABASE_ANON_KEY"
- Verify you're using one of the run scripts or passing `--dart-define` flags
- Check `.env.flutter.local` exists and contains valid credentials
- Restart Flutter app after updating credentials

### Generic Queries Return Low Similarity (0%)
- **This is expected** when using session fallback
- Generic queries ("what does code do") often have low semantic match
- The system provides contextual preambles to compensate
- Review `is_generic_query` flag in response

### Enriched Chunks Not Visible  
- Metadata is added to embeddings, not stored separately
- Chunks are displayed with their original text in UI
- Metadata helps with search, not chunk display
- Check logs for enrichment confirmation

### Session Cache Not Working
- Ensure files were ingested in this session (check `.session_chunk_cache.json`)
- Cache expires after `SESSION_TTL_SECONDS` (default 30 mins)
- Try uploading a file again to repopulate cache

---

## Performance Tips

1. **For Better Generic Query Results**: Upload multiple related files so session cache is rich
2. **For Faster Searches**: Specific queries with function/class names work best
3. **Session Management**: Cache holds up to 200 chunks per session
4. **Embedding Cost**: Enrichment adds ~15-20% metadata to embeddings (minimal overhead)

---

## Next Steps

1. Configure Supabase credentials using one of the setup options above
2. Run: `.\run_with_supabase.ps1 -supabaseUrl "..." -supabaseAnonKey "..."`
3. Upload a Python file to test chunking
4. Try a generic query like "what does this code do"
5. Observe enriched metadata in retrieved chunks and answers

See backend logs for details on enrichment, genericity detection, and context building.
