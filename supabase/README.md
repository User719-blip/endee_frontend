Supabase setup for the Flutter app

1. Create a Supabase project.
2. Set these Supabase secrets:

```powershell
supabase secrets set HF_API_KEY=your_huggingface_token
supabase secrets set ENDEE_API_KEY=your_endee_key
supabase secrets set ENDEE_BASE_URL=https://app.endee.io
supabase secrets set ENDEE_COLLECTION_NAME=codebase
```

3. Deploy the Edge Functions from `supabase/functions/*`.
4. Run the Flutter app with:

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

The Flutter app calls these edge functions:

- `embed` for Hugging Face embeddings.
- `store_document` to insert a chunk into Endee.
- `search_documents` to run Endee similarity search.
- `answer` to generate the final response.

If Endee is required as the vector store, you do not need the SQL migration or the `vector` extension path.

The function configs set `verify_jwt = false`, so the Flutter app can call them with the Supabase publishable key and `apikey` header.