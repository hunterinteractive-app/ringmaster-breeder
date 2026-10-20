-- Saved source/breeder evidence. No existing animal is assigned inferred genes.
-- Existing animals ownership RLS, revision triggers and grants remain in force.
alter table public.animals
  add column genotype jsonb not null default '{}'::jsonb;

alter table public.animals add constraint animals_genotype_record_check check (
  jsonb_typeof(genotype) = 'object'
  and (
    genotype = '{}'::jsonb
    or coalesce((
      genotype - array['notation','basis','source'] = '{}'::jsonb
      and jsonb_typeof(genotype->'notation') = 'string'
      and length(btrim(genotype->>'notation')) between 1 and 500
      and jsonb_typeof(genotype->'basis') = 'string'
      and genotype->>'basis' in ('breeder_entered','imported','inferred')
      and (
        not (genotype ? 'source')
        or (jsonb_typeof(genotype->'source') = 'string'
            and length(genotype->>'source') <= 300)
      )
    ), false)
  )
);

comment on column public.animals.genotype is
  'Breeder-entered/imported/inferred reference notation and its source. Unknown symbols are preserved. Not proof of a complete genotype. Compatible readable genes constrain predictions; unknowns remain unresolved.';
