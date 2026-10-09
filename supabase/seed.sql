-- =============================================================================
--  Données de démonstration — UNIQUEMENT pour la base locale (supabase start / db reset)
-- =============================================================================
--  Comptes (mot de passe : motdepasse123) :
--    alice@colloc.test, bob@colloc.test, chloe@colloc.test, dan@colloc.test
--      → membres de « Coloc des Alpes » (code GAPDEMXV27), Alice est admin
--    eve@colloc.test → seule dans « Coloc d'Ève » : sert au test d'intrusion du jalon 2
--
--  Les 5 dépenses sont le jeu de test du jalon 3 (calcul à la main : docs/jalon3.md).
-- =============================================================================

-- Identifiants fixes et triés (a… < b… < c… < d…) : le centime restant d'une
-- répartition égale va donc toujours au premier participant dans cet ordre.
create temporary table comptes (id uuid, email text, pseudo text) on commit drop;
insert into comptes values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'alice@colloc.test', 'Alice'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'bob@colloc.test',   'Bob'),
  ('cccccccc-0000-4000-8000-000000000003', 'chloe@colloc.test', 'Chloé'),
  ('dddddddd-0000-4000-8000-000000000004', 'dan@colloc.test',   'Dan'),
  ('eeeeeeee-0000-4000-8000-000000000005', 'eve@colloc.test',   'Ève');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
  extensions.crypt('motdepasse123', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', jsonb_build_object('pseudo', pseudo), now(), now(),
  '', '', '', ''
from comptes;

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), id, id::text,
       jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true),
       'email', now(), now(), now()
from comptes;
-- (les profils sont créés par le trigger creer_profil_apres_inscription)

insert into public.colocations (id, nom, code_invitation, cree_par) values
  ('11111111-0000-4000-8000-000000000001', 'Coloc des Alpes', 'GAPDEMXV27', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('22222222-0000-4000-8000-000000000002', 'Coloc d''Ève',    'EVEKHZ4R9T', 'eeeeeeee-0000-4000-8000-000000000005');

insert into public.membres (colocation_id, utilisateur_id, role, rejoint_le) values
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'admin',  now() - interval '30 days'),
  ('11111111-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002', 'membre', now() - interval '29 days'),
  ('11111111-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000003', 'membre', now() - interval '28 days'),
  ('11111111-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000004', 'membre', now() - interval '27 days'),
  ('22222222-0000-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000005', 'admin',  now() - interval '10 days');

-- Jeu de test du jalon 3 : 4 personnes, 5 dépenses, parts inégales -----------
-- A = Alice, B = Bob, C = Chloé, D = Dan (montants en centimes)
create temporary table jeu (n int, payeur uuid, montant int, description text, jour date, parts jsonb) on commit drop;
insert into jeu values
  -- 1. 84,60 € payés par A, parts égales entre A, B, C, D → 2115 chacun
  (1, 'aaaaaaaa-0000-4000-8000-000000000001', 8460, 'Courses Carrefour', current_date - 12,
   '{"aaaaaaaa-0000-4000-8000-000000000001":2115,"bbbbbbbb-0000-4000-8000-000000000002":2115,"cccccccc-0000-4000-8000-000000000003":2115,"dddddddd-0000-4000-8000-000000000004":2115}'),
  -- 2. 120,00 € payés par B, parts perso : A 40 €, B 40 €, C 20 €, D 20 €
  (2, 'bbbbbbbb-0000-4000-8000-000000000002', 12000, 'Électricité', current_date - 9,
   '{"aaaaaaaa-0000-4000-8000-000000000001":4000,"bbbbbbbb-0000-4000-8000-000000000002":4000,"cccccccc-0000-4000-8000-000000000003":2000,"dddddddd-0000-4000-8000-000000000004":2000}'),
  -- 3. 37,00 € payés par C, parts égales entre A, C, D → 1234 (A, 1er trié), 1233, 1233
  (3, 'cccccccc-0000-4000-8000-000000000003', 3700, 'Pizzas', current_date - 6,
   '{"aaaaaaaa-0000-4000-8000-000000000001":1234,"cccccccc-0000-4000-8000-000000000003":1233,"dddddddd-0000-4000-8000-000000000004":1233}'),
  -- 4. 29,99 € payés par D, parts égales entre les 4 → 750, 750, 750, 749
  (4, 'dddddddd-0000-4000-8000-000000000004', 2999, 'Box internet', current_date - 4,
   '{"aaaaaaaa-0000-4000-8000-000000000001":750,"bbbbbbbb-0000-4000-8000-000000000002":750,"cccccccc-0000-4000-8000-000000000003":750,"dddddddd-0000-4000-8000-000000000004":749}'),
  -- 5. 15,50 € payés par A, parts perso : B 10,00 €, D 5,50 €
  (5, 'aaaaaaaa-0000-4000-8000-000000000001', 1550, 'Produits ménagers', current_date - 2,
   '{"bbbbbbbb-0000-4000-8000-000000000002":1000,"dddddddd-0000-4000-8000-000000000004":550}');

insert into public.depenses (id, colocation_id, payeur_id, montant_centimes, description, date_depense, cree_par)
select ('00000000-0000-4000-8000-00000000000' || n)::uuid, '11111111-0000-4000-8000-000000000001',
       payeur, montant, description, jour, payeur
from jeu;

insert into public.depense_parts (depense_id, colocation_id, utilisateur_id, montant_centimes)
select ('00000000-0000-4000-8000-00000000000' || j.n)::uuid, '11111111-0000-4000-8000-000000000001',
       p.key::uuid, p.value::int
from jeu j, jsonb_each_text(j.parts) p;

-- Un peu de vie dans les autres onglets ---------------------------------------
insert into public.taches (colocation_id, titre, frequence, responsable_id, prochaine_echeance, cree_par) values
  ('11111111-0000-4000-8000-000000000001', 'Sortir les poubelles', 'hebdomadaire', 'bbbbbbbb-0000-4000-8000-000000000002', current_date - 1, 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('11111111-0000-4000-8000-000000000001', 'Vaisselle',            'quotidienne',  'cccccccc-0000-4000-8000-000000000003', current_date,     'aaaaaaaa-0000-4000-8000-000000000001'),
  ('11111111-0000-4000-8000-000000000001', 'Ménage salle de bain', 'hebdomadaire', 'aaaaaaaa-0000-4000-8000-000000000001', current_date + 3, 'bbbbbbbb-0000-4000-8000-000000000002');

insert into public.articles_courses (colocation_id, libelle, quantite, ajoute_par) values
  ('11111111-0000-4000-8000-000000000001', 'Lait',          '2 L', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('11111111-0000-4000-8000-000000000001', 'Pâtes',         '1 kg', 'bbbbbbbb-0000-4000-8000-000000000002'),
  ('11111111-0000-4000-8000-000000000001', 'Papier toilette', null, 'dddddddd-0000-4000-8000-000000000004');

insert into public.messages (colocation_id, auteur_id, contenu, envoye_le)
select '11111111-0000-4000-8000-000000000001',
       (array['aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002',
              'cccccccc-0000-4000-8000-000000000003', 'dddddddd-0000-4000-8000-000000000004'])[1 + i % 4]::uuid,
       'Message de démonstration n° ' || i,
       now() - (80 - i) * interval '1 hour'
from generate_series(1, 80) as i;
