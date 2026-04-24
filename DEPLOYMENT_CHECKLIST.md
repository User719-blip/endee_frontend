# Deployment Checklist (Frontend + Backend Split)

Use this when pushing frontend and backend into separate GitHub repositories.

## 1) Frontend Repo (GitHub Pages)

1. Create a new repo for frontend.
2. Copy frontend files (Flutter app) and exclude backend folder.
3. Ensure build command works:
   - `flutter pub get`
   - `flutter build web --release --base-href /<repo-name>/`
4. Deploy `build/web` to GitHub Pages.
5. Pass runtime defines during build/deploy:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `PY_BACKEND_URL` (Render backend URL)

#ALTERNATE (using github action)

1. Create a workflow 
2. Insert ENV values into file:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `PY_BACKEND_URL` (Render backend URL)
3. Trigger on push

workflow methord is used here in this project check `.github\workflows`


## 2) Backend Repo (Render)

1. Create a new repo for backend only (`backend/` contents).
2. Add `requirements.txt`, `main.py`, `models.py`, `session_store.py`, `README.md`, `.env.example`, `flow.md`.
3. Render settings:
   - Build command: `pip install -r requirements.txt`
   - Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
4. Configure environment variables in Render:
   - `ENDEE_TOKEN`
   - `ENDEE_INDEX_NAME`
   - `ENDEE_INDEX_SPACE_TYPE`
   - `ENDEE_INDEX_PRECISION`
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_EMBED_FUNCTION=embed`
   - `SESSION_TTL_SECONDS`

## 3) Supabase Edge Functions

Required edge functions:

- `embed`:
  - Input: `text`
  - Output: `embedding`
- `answer`:
  - Input: `context`, `question`, optional `stream=true`
  - Output: final answer JSON or streamed SSE tokens

Required Supabase secret:

- `HF_API_KEY` (Hugging Face token)

## 4) Frontend-to-Backend Connectivity Check

1. Open frontend app.
2. Upload file/zip.
3. Ask question (< 100 words).
4. Confirm response streams token-by-token.
5. Confirm retrieval is fixed to top 3 chunks.