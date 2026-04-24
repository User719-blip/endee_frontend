create extension if not exists vector;

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  file text not null,
  content text not null,
  embedding vector(384) not null,
  created_at timestamptz not null default now()
);

create index if not exists documents_embedding_idx
  on public.documents
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

create or replace function public.match_documents(
  query_embedding vector(384),
  match_count int default 3
)
returns table (
  id uuid,
  file text,
  content text,
  similarity float
)
language sql
stable
as $$
  select
    documents.id,
    documents.file,
    documents.content,
    1 - (documents.embedding <=> query_embedding) as similarity
  from public.documents
  order by documents.embedding <=> query_embedding
  limit match_count;
$$;