-- Tests de la base (pgTAP), sur les données de supabase/seed.sql.
-- Lancement : supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- On se met dans la peau d'Alice (membre de la Coloc des Alpes)
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}';

select results_eq(
  $$ select utilisateur_id::text, solde_centimes from public.soldes
     where colocation_id = '11111111-0000-4000-8000-000000000001' order by utilisateur_id $$,
  $$ values ('aaaaaaaa-0000-4000-8000-000000000001', 1911::bigint),
            ('bbbbbbbb-0000-4000-8000-000000000002', 4135::bigint),
            ('cccccccc-0000-4000-8000-000000000003', -2398::bigint),
            ('dddddddd-0000-4000-8000-000000000004', -3648::bigint) $$,
  'Jalon 3 : les soldes calculés par la base sont ceux prédits sur papier'
);

select is(
  (select sum(solde_centimes) from public.soldes where colocation_id = '11111111-0000-4000-8000-000000000001'),
  0::numeric,
  'Jalon 3 : la somme des soldes vaut exactement 0'
);

select lives_ok(
  $$ select public.creer_depense(
       '11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 1000, 'Test arrondi',
       current_date, array['aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002',
                           'cccccccc-0000-4000-8000-000000000003']::uuid[]) $$,
  'Création d''une dépense de 10 € entre 3 personnes'
);

select results_eq(
  $$ select p.montant_centimes from public.depense_parts p
     join public.depenses d on d.id = p.depense_id
     where d.description = 'Test arrondi' order by p.utilisateur_id $$,
  $$ values (334), (333), (333) $$,
  '10 € entre 3 : 334 + 333 + 333, le centime restant va au premier participant trié'
);

-- Le contrôle « somme des parts = montant » est différé au COMMIT. La transaction
-- de test étant annulée à la fin, on simule le COMMIT avec SET CONSTRAINTS IMMEDIATE.
select lives_ok(
  $$ select public.creer_depense('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
       1000, 'Parts fausses', current_date,
       array['aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002']::uuid[],
       array[300, 300]) $$,
  'Dépense mal répartie : acceptée provisoirement dans la transaction…'
);
select throws_ok(
  $$ set constraints all immediate $$,
  '23514', null,
  '… puis refusée au moment de valider (somme des parts ≠ montant)'
);

-- Ève n'est pas membre de la Coloc des Alpes
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-4000-8000-000000000005","role":"authenticated"}';

select is_empty(
  $$ select 1 from public.depenses where colocation_id = '11111111-0000-4000-8000-000000000001' $$,
  'Ève ne voit pas les dépenses d''une autre coloc'
);
select is_empty(
  $$ select 1 from public.soldes where colocation_id = '11111111-0000-4000-8000-000000000001' $$,
  'Ève ne voit pas les soldes d''une autre coloc'
);
select is_empty(
  $$ select 1 from public.messages where colocation_id = '11111111-0000-4000-8000-000000000001' $$,
  'Ève ne voit pas les messages d''une autre coloc'
);
select throws_ok(
  $$ insert into public.membres (colocation_id, utilisateur_id)
     values ('11111111-0000-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000005') $$,
  '42501', null,
  'Ève ne peut pas s''ajouter elle-même à une coloc'
);
select throws_ok(
  $$ select public.retirer_membre('11111111-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002') $$,
  '42501', null,
  'Ève ne peut pas retirer un membre d''une coloc qui n''est pas la sienne'
);

select * from finish();
rollback;
