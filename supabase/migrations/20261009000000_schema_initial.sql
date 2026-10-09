-- =============================================================================
--  Colloc' — schéma de la base de données (Supabase / PostgreSQL 15+)
-- =============================================================================
--  À exécuter EN UNE FOIS dans Supabase → SQL Editor, sur un projet vide,
--  de préférence avant de créer les comptes de test.
--
--  Principes (justifiés dans DECISIONS.md) :
--    • montants en centimes entiers ;
--    • toute la sécurité est en base : RLS sur chaque table + droits par colonne ;
--    • les opérations sensibles ou multi-tables passent par des fonctions (RPC),
--      exécutées en une seule transaction ;
--    • les fonctions utilisées par les policies sont dans le schéma « prive »,
--      que l'API REST n'expose pas.
--
--  Sommaire : 1. Tables   2. Fonctions internes   3. Triggers   4. Vue des soldes
--             5. RPC      6. RLS                  7. Droits     8. Storage
--             9. Realtime
-- =============================================================================

create schema if not exists prive;
revoke all on schema prive from public;
grant usage on schema prive to authenticated;


-- =============================================================================
-- 1. TABLES
-- =============================================================================

create table public.profils (
  id             uuid primary key references auth.users (id) on delete cascade,
  pseudo         text not null check (char_length(trim(pseudo)) between 1 and 30),
  avatar_chemin  text,
  cree_le        timestamptz not null default now(),
  -- l'avatar doit être rangé dans le dossier de l'utilisateur (bucket « avatars »)
  check (avatar_chemin is null or avatar_chemin like id::text || '/%')
);

create table public.colocations (
  id               uuid primary key default gen_random_uuid(),
  nom              text not null check (char_length(trim(nom)) between 1 and 60),
  code_invitation  text not null unique check (code_invitation ~ '^[A-HJ-NP-Z2-9]{10}$'),
  cree_par         uuid references public.profils (id) on delete set null,
  cree_le          timestamptz not null default now()
);

-- Appartenance d'un utilisateur à une coloc, avec son rôle.
-- Un départ ne supprime pas la ligne (parti_le) : l'historique des dépenses reste valide.
create table public.membres (
  colocation_id          uuid not null references public.colocations (id) on delete cascade,
  utilisateur_id         uuid not null references public.profils (id) on delete cascade,
  role                   text not null default 'membre' check (role in ('admin', 'membre')),
  rejoint_le             timestamptz not null default now(),
  parti_le               timestamptz,            -- null = membre actif
  dernier_message_lu_id  bigint,                 -- pour l'indicateur de nouveaux messages
  primary key (colocation_id, utilisateur_id),
  check (parti_le is null or parti_le >= rejoint_le)
);

-- Un seul admin actif par coloc
create unique index membres_un_seul_admin on public.membres (colocation_id)
  where role = 'admin' and parti_le is null;
create index membres_par_utilisateur on public.membres (utilisateur_id)
  where parti_le is null;

create table public.depenses (
  id                uuid primary key default gen_random_uuid(),
  colocation_id     uuid not null references public.colocations (id) on delete cascade,
  payeur_id         uuid not null,
  montant_centimes  integer not null check (montant_centimes between 1 and 100000000),
  description       text not null check (char_length(trim(description)) between 1 and 200),
  date_depense      date not null default current_date,
  ticket_chemin     text,
  cree_par          uuid not null default auth.uid() references public.profils (id),
  cree_le           timestamptz not null default now(),
  unique (id, colocation_id),
  -- le payeur est forcément un membre (actuel ou ancien) de CETTE coloc.
  -- Clé « différée » (vérifiée au COMMIT) comme toutes celles vers membres : sinon,
  -- supprimer une coloc échoue, car Postgres ne garantit pas l'ordre des cascades.
  foreign key (colocation_id, payeur_id) references public.membres (colocation_id, utilisateur_id) deferrable initially deferred,
  -- la photo du ticket doit être rangée dans le dossier de la coloc (bucket « tickets »)
  check (ticket_chemin is null or ticket_chemin like colocation_id::text || '/%')
);
create index depenses_par_coloc on public.depenses (colocation_id, date_depense desc);

-- Répartition d'une dépense : une ligne par participant.
-- La somme des parts est toujours égale au montant (trigger différé, section 3).
create table public.depense_parts (
  depense_id        uuid not null,
  colocation_id     uuid not null,
  utilisateur_id    uuid not null,
  montant_centimes  integer not null check (montant_centimes >= 0),
  primary key (depense_id, utilisateur_id),
  -- la part appartient à une dépense de la même coloc…
  foreign key (depense_id, colocation_id) references public.depenses (id, colocation_id) on delete cascade,
  -- …et concerne un membre de cette coloc
  foreign key (colocation_id, utilisateur_id) references public.membres (colocation_id, utilisateur_id) deferrable initially deferred
);
create index depense_parts_par_membre on public.depense_parts (colocation_id, utilisateur_id);

create table public.remboursements (
  id                uuid primary key default gen_random_uuid(),
  colocation_id     uuid not null references public.colocations (id) on delete cascade,
  debiteur_id       uuid not null,   -- celui qui rembourse
  crediteur_id      uuid not null,   -- celui qui reçoit
  montant_centimes  integer not null check (montant_centimes between 1 and 100000000),
  cree_par          uuid not null default auth.uid() references public.profils (id),
  cree_le           timestamptz not null default now(),
  check (debiteur_id <> crediteur_id),
  foreign key (colocation_id, debiteur_id) references public.membres (colocation_id, utilisateur_id) deferrable initially deferred,
  foreign key (colocation_id, crediteur_id) references public.membres (colocation_id, utilisateur_id) deferrable initially deferred
);
create index remboursements_par_coloc on public.remboursements (colocation_id);

-- Tâche récurrente. La rotation = le responsable actuel + l'ordre d'arrivée des membres.
create table public.taches (
  id                  uuid primary key default gen_random_uuid(),
  colocation_id       uuid not null references public.colocations (id) on delete cascade,
  titre               text not null check (char_length(trim(titre)) between 1 and 80),
  frequence           text not null check (frequence in ('quotidienne', 'hebdomadaire')),
  responsable_id      uuid not null,
  prochaine_echeance  date not null,
  cree_par            uuid not null default auth.uid() references public.profils (id),
  cree_le             timestamptz not null default now(),
  foreign key (colocation_id, responsable_id) references public.membres (colocation_id, utilisateur_id) deferrable initially deferred
);
create index taches_par_coloc on public.taches (colocation_id, prochaine_echeance);

-- Historique des tâches faites (rempli uniquement par la RPC terminer_tache)
create table public.tache_realisations (
  id                 uuid primary key default gen_random_uuid(),
  tache_id           uuid not null references public.taches (id) on delete cascade,
  colocation_id      uuid not null references public.colocations (id) on delete cascade,
  fait_par           uuid not null references public.profils (id),
  responsable_prevu  uuid not null references public.profils (id),
  echeance           date not null,
  en_retard          boolean not null,
  fait_le            timestamptz not null default now()
);
create index tache_realisations_par_tache on public.tache_realisations (tache_id, fait_le desc);

create table public.articles_courses (
  id             uuid primary key default gen_random_uuid(),
  colocation_id  uuid not null references public.colocations (id) on delete cascade,
  libelle        text not null check (char_length(trim(libelle)) between 1 and 100),
  quantite       text check (char_length(quantite) <= 30),
  ajoute_par     uuid not null default auth.uid() references public.profils (id),
  ajoute_le      timestamptz not null default now(),
  coche          boolean not null default false,
  coche_par      uuid references public.profils (id),   -- rempli par trigger, jamais par le client
  coche_le       timestamptz,
  check ((coche and coche_par is not null and coche_le is not null)
      or (not coche and coche_par is null and coche_le is null))
);
create index articles_courses_par_coloc on public.articles_courses (colocation_id, ajoute_le);

-- Identifiant séquentiel : sert à la pagination (id < dernier_id) et aux « non lus »
create table public.messages (
  id             bigint generated always as identity primary key,
  colocation_id  uuid not null references public.colocations (id) on delete cascade,
  auteur_id      uuid not null default auth.uid() references public.profils (id),
  contenu        text not null check (char_length(trim(contenu)) between 1 and 2000),
  envoye_le      timestamptz not null default now()
);
create index messages_par_coloc on public.messages (colocation_id, id desc);


-- =============================================================================
-- 2. FONCTIONS INTERNES (schéma prive, non exposé par l'API)
-- =============================================================================
-- Les fonctions SECURITY DEFINER lisent « membres » sans repasser par sa RLS :
-- c'est ce qui évite la récursion infinie quand la policy de « membres » doit
-- elle-même consulter « membres ». Elles ne répondent que pour l'utilisateur
-- connecté (auth.uid()), donc ne divulguent rien.

-- Colocations dont l'utilisateur connecté est membre actif
create function prive.mes_colocations()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select colocation_id from public.membres
  where utilisateur_id = (select auth.uid()) and parti_le is null
$$;

create function prive.est_membre_actif(p_colocation_id uuid, p_utilisateur_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.membres
    where colocation_id = p_colocation_id
      and utilisateur_id = p_utilisateur_id
      and parti_le is null
  )
$$;

create function prive.est_admin(p_colocation_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.membres
    where colocation_id = p_colocation_id
      and utilisateur_id = (select auth.uid())
      and role = 'admin'
      and parti_le is null
  )
$$;

-- Vrai si l'utilisateur donné est (ou a été) membre d'une coloc où je suis actif
create function prive.partage_une_coloc(p_utilisateur_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.membres moi
    join public.membres autre on autre.colocation_id = moi.colocation_id
    where moi.utilisateur_id = (select auth.uid())
      and moi.parti_le is null
      and autre.utilisateur_id = p_utilisateur_id
  )
$$;

-- Conversion tolérante pour les noms de dossiers Storage : texte invalide → null
create function prive.uuid_ou_null(p_texte text)
returns uuid
language plpgsql immutable set search_path = ''
as $$
begin
  return p_texte::uuid;
exception when invalid_text_representation then
  return null;
end
$$;

-- Code d'invitation : 10 caractères parmi 32 (sans 0, O, 1, I), soit 2^50 possibilités.
-- L'aléa vient de gen_random_uuid(), qui utilise une source cryptographique.
create function prive.generer_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  v_alphabet constant text  := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_octets   constant bytea := uuid_send(gen_random_uuid());
  v_code     text := '';
  v_i        integer;
begin
  -- on saute les octets 6 et 8, qui portent la version et la variante de l'UUID
  foreach v_i in array array[0, 1, 2, 3, 4, 5, 7, 9, 10, 11] loop
    v_code := v_code || substr(v_alphabet, get_byte(v_octets, v_i) % 32 + 1, 1);
  end loop;
  return v_code;
end
$$;

-- « Aujourd'hui » à l'heure française (le serveur Supabase est en UTC)
create function prive.aujourdhui()
returns date
language sql stable set search_path = ''
as $$
  select (now() at time zone 'Europe/Paris')::date
$$;

-- Membre actif qui suit p_utilisateur_id dans la rotation (ordre d'arrivée),
-- en revenant au début après le dernier. Marche même si p_utilisateur_id est parti.
create function prive.membre_suivant(p_colocation_id uuid, p_utilisateur_id uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select m.utilisateur_id
  from public.membres m
  where m.colocation_id = p_colocation_id and m.parti_le is null
  order by
    -- d'abord ceux arrivés après lui (false trie avant true), puis retour au début
    (m.rejoint_le, m.utilisateur_id) <= (
      select r.rejoint_le, r.utilisateur_id from public.membres r
      where r.colocation_id = p_colocation_id and r.utilisateur_id = p_utilisateur_id
    ),
    m.rejoint_le,
    m.utilisateur_id
  limit 1
$$;

-- Départ d'un membre : sa ligne reste (historique), il perd l'accès,
-- et ses tâches passent au membre suivant.
create function prive.enregistrer_depart(p_colocation_id uuid, p_utilisateur_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.membres
  set parti_le = now(), role = 'membre'
  where colocation_id = p_colocation_id
    and utilisateur_id = p_utilisateur_id
    and parti_le is null;

  update public.taches
  set responsable_id = prive.membre_suivant(colocation_id, responsable_id)
  where colocation_id = p_colocation_id
    and responsable_id = p_utilisateur_id;
end
$$;

create function prive.pseudo_initial(p_meta jsonb, p_email text)
returns text
language sql immutable set search_path = ''
as $$
  select left(coalesce(
    nullif(trim(p_meta ->> 'pseudo'), ''),
    nullif(split_part(coalesce(p_email, ''), '@', 1), ''),
    'Coloc'
  ), 30)
$$;

-- Vérifie qu'une dépense est entièrement répartie (appelée au COMMIT, voir section 3)
create function prive.controler_depense(p_depense_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_total  integer;
  v_somme  bigint;
begin
  select montant_centimes into v_total from public.depenses where id = p_depense_id;
  if not found then
    return;  -- dépense supprimée entre-temps : rien à vérifier
  end if;

  select coalesce(sum(montant_centimes), 0) into v_somme
  from public.depense_parts where depense_id = p_depense_id;

  if v_somme <> v_total then
    raise exception 'La somme des parts (% centimes) doit être égale au montant de la dépense (% centimes)',
      v_somme, v_total
      using errcode = '23514';  -- check_violation
  end if;
end
$$;


-- =============================================================================
-- 3. TRIGGERS
-- =============================================================================

-- Profil créé automatiquement à l'inscription (pseudo = métadonnée « pseudo »)
create function prive.creer_profil()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profils (id, pseudo)
  values (new.id, prive.pseudo_initial(new.raw_user_meta_data, new.email));
  return new;
end
$$;

create trigger creer_profil_apres_inscription
  after insert on auth.users
  for each row execute function prive.creer_profil();

-- Comptes créés avant ce script : on leur crée aussi un profil
insert into public.profils (id, pseudo)
select id, prive.pseudo_initial(raw_user_meta_data, email) from auth.users
on conflict (id) do nothing;

-- Qui a coché quoi : rempli par la base, le client ne peut pas mentir
create function prive.horodater_coche()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.coche is distinct from old.coche then
    if new.coche then
      new.coche_par := auth.uid();
      new.coche_le  := now();
    else
      new.coche_par := null;
      new.coche_le  := null;
    end if;
  end if;
  return new;
end
$$;

create trigger horodater_coche
  before update on public.articles_courses
  for each row execute function prive.horodater_coche();

-- Somme des parts = montant : vérifié au COMMIT (trigger différé), donc après que
-- la dépense ET toutes ses parts ont été insérées dans la même transaction.
create function prive.verifier_parts_modifiees()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform prive.controler_depense(old.depense_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform prive.controler_depense(new.depense_id);
  end if;
  return null;
end
$$;

create constraint trigger parts_coherentes
  after insert or update or delete on public.depense_parts
  deferrable initially deferred
  for each row execute function prive.verifier_parts_modifiees();

create function prive.verifier_depense_modifiee()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform prive.controler_depense(new.id);
  return null;
end
$$;

create constraint trigger depense_entierement_repartie
  after insert or update of montant_centimes on public.depenses
  deferrable initially deferred
  for each row execute function prive.verifier_depense_modifiee();


-- =============================================================================
-- 4. VUE DES SOLDES
-- =============================================================================
-- Solde > 0 : on doit de l'argent à ce membre. Solde < 0 : il doit de l'argent.
-- Tout est en entiers, donc la somme des soldes d'une coloc vaut exactement 0.
-- security_invoker : la RLS des tables lues s'applique à celui qui interroge la vue.
create view public.soldes with (security_invoker = true) as
with mouvements as (
  select colocation_id, payeur_id as utilisateur_id, montant_centimes::bigint as montant
  from public.depenses
  union all
  select colocation_id, utilisateur_id, -montant_centimes
  from public.depense_parts
  union all
  select colocation_id, debiteur_id, montant_centimes
  from public.remboursements
  union all
  select colocation_id, crediteur_id, -montant_centimes
  from public.remboursements
)
select
  m.colocation_id,
  m.utilisateur_id,
  m.parti_le is not null                  as a_quitte,
  coalesce(sum(mv.montant), 0)::bigint    as solde_centimes
from public.membres m
left join mouvements mv
  on mv.colocation_id = m.colocation_id and mv.utilisateur_id = m.utilisateur_id
group by m.colocation_id, m.utilisateur_id, m.parti_le;


-- =============================================================================
-- 5. RPC (appelées depuis Flutter avec supabase.rpc('nom', params: {...}))
-- =============================================================================

create function public.creer_colocation(p_nom text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;

  insert into public.colocations (nom, code_invitation, cree_par)
  values (trim(p_nom), prive.generer_code(), v_uid)
  returning id into v_id;

  insert into public.membres (colocation_id, utilisateur_id, role)
  values (v_id, v_uid, 'admin');

  return v_id;
end
$$;

-- Seul moyen d'entrer dans une coloc dont on ne peut encore rien lire
create function public.rejoindre_colocation(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_coloc  uuid;
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;

  -- tolère minuscules, espaces et tirets saisis par l'utilisateur
  select id into v_coloc
  from public.colocations
  where code_invitation = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  if v_coloc is null then
    raise exception 'Code d''invitation invalide' using errcode = 'P0002';
  end if;

  -- nouveau membre, ou ancien membre qui revient
  insert into public.membres (colocation_id, utilisateur_id, role)
  values (v_coloc, v_uid, 'membre')
  on conflict (colocation_id, utilisateur_id) do update
    set parti_le = null, rejoint_le = now(), role = 'membre'
    where public.membres.parti_le is not null;

  return v_coloc;
end
$$;

create function public.regenerer_code(p_colocation_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_code  text := prive.generer_code();
begin
  if not prive.est_admin(p_colocation_id) then
    raise exception 'Seul l''admin peut régénérer le code' using errcode = '42501';
  end if;

  update public.colocations set code_invitation = v_code where id = p_colocation_id;
  return v_code;
end
$$;

create function public.retirer_membre(p_colocation_id uuid, p_utilisateur_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not prive.est_admin(p_colocation_id) then
    raise exception 'Seul l''admin peut retirer un membre' using errcode = '42501';
  end if;
  if p_utilisateur_id = auth.uid() then
    raise exception 'Pour partir, utilisez « Quitter la colocation »' using errcode = '22023';
  end if;
  if not prive.est_membre_actif(p_colocation_id, p_utilisateur_id) then
    raise exception 'Ce membre ne fait pas partie de la colocation' using errcode = 'P0002';
  end if;

  perform prive.enregistrer_depart(p_colocation_id, p_utilisateur_id);
end
$$;

create function public.quitter_colocation(p_colocation_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid          uuid := auth.uid();
  v_etait_admin  boolean := prive.est_admin(p_colocation_id);
begin
  if not prive.est_membre_actif(p_colocation_id, v_uid) then
    raise exception 'Vous n''êtes pas membre de cette colocation' using errcode = '42501';
  end if;

  -- dernier membre : la coloc n'a plus de raison d'exister
  if not exists (
    select 1 from public.membres
    where colocation_id = p_colocation_id and parti_le is null and utilisateur_id <> v_uid
  ) then
    delete from public.colocations where id = p_colocation_id;
    return;
  end if;

  perform prive.enregistrer_depart(p_colocation_id, v_uid);

  -- l'admin s'en va : le plus ancien membre restant prend le relais
  if v_etait_admin then
    update public.membres set role = 'admin'
    where colocation_id = p_colocation_id
      and utilisateur_id = (
        select utilisateur_id from public.membres
        where colocation_id = p_colocation_id and parti_le is null
        order by rejoint_le, utilisateur_id
        limit 1
      );
  end if;
end
$$;

-- Crée une dépense ET ses parts dans une seule transaction (tout ou rien).
-- p_montants = null → parts égales ; sinon un montant en centimes par participant.
-- SECURITY INVOKER : les policies RLS s'appliquent exactement comme pour un insert direct.
create function public.creer_depense(
  p_colocation_id     uuid,
  p_payeur_id         uuid,
  p_montant_centimes  integer,
  p_description       text,
  p_date              date,
  p_participants      uuid[],
  p_montants          integer[] default null,
  p_ticket_chemin     text default null
)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare
  v_id  uuid;
  v_nb  integer := coalesce(cardinality(p_participants), 0);
begin
  if v_nb = 0 then
    raise exception 'Choisissez au moins un participant' using errcode = '22023';
  end if;
  if v_nb <> (select count(distinct p) from unnest(p_participants) as p) then
    raise exception 'Un participant apparaît deux fois' using errcode = '22023';
  end if;
  if p_montants is not null and cardinality(p_montants) <> v_nb then
    raise exception 'Il faut un montant par participant' using errcode = '22023';
  end if;

  insert into public.depenses
    (colocation_id, payeur_id, montant_centimes, description, date_depense, ticket_chemin)
  values
    (p_colocation_id, p_payeur_id, p_montant_centimes, trim(p_description),
     coalesce(p_date, current_date), p_ticket_chemin)
  returning id into v_id;

  if p_montants is null then
    -- Parts égales : les centimes restants vont, un par un, aux premiers participants
    -- triés par identifiant (même résultat quel que soit l'appareil).
    -- Ex. 1000 centimes / 3 → 334, 333, 333.
    insert into public.depense_parts (depense_id, colocation_id, utilisateur_id, montant_centimes)
    select v_id, p_colocation_id, t.u,
           p_montant_centimes / v_nb
             + case when t.rang <= p_montant_centimes % v_nb then 1 else 0 end
    from (
      select u, row_number() over (order by u) as rang
      from unnest(p_participants) as u
    ) as t;
  else
    insert into public.depense_parts (depense_id, colocation_id, utilisateur_id, montant_centimes)
    select v_id, p_colocation_id, t.u, t.m
    from unnest(p_participants, p_montants) as t(u, m);
  end if;

  return v_id;
end
$$;

-- Marque une tâche comme faite : historique + échéance suivante + membre suivant,
-- en une transaction. Le verrou (for update) gère deux clics simultanés.
create function public.terminer_tache(p_tache_id uuid)
returns public.taches
language plpgsql security definer set search_path = ''
as $$
declare
  v_tache  public.taches;
  v_jour   date := prive.aujourdhui();
  v_pas    integer;
begin
  select * into v_tache from public.taches where id = p_tache_id for update;
  if not found or not prive.est_membre_actif(v_tache.colocation_id, auth.uid()) then
    raise exception 'Tâche introuvable' using errcode = 'P0002';
  end if;

  insert into public.tache_realisations
    (tache_id, colocation_id, fait_par, responsable_prevu, echeance, en_retard)
  values
    (v_tache.id, v_tache.colocation_id, auth.uid(), v_tache.responsable_id,
     v_tache.prochaine_echeance, v_jour > v_tache.prochaine_echeance);

  -- garde le rythme (ex. « tous les lundis ») en sautant les périodes déjà dépassées
  v_pas := case v_tache.frequence when 'quotidienne' then 1 else 7 end;

  update public.taches
  set prochaine_echeance = prochaine_echeance
                           + v_pas * (greatest(0, v_jour - prochaine_echeance) / v_pas + 1),
      responsable_id     = prive.membre_suivant(colocation_id, responsable_id)
  where id = p_tache_id
  returning * into v_tache;

  return v_tache;
end
$$;


-- =============================================================================
-- 6. RLS — traduction de la matrice d'autorisations (docs/conception.md)
-- =============================================================================
-- Aucune policy pour « anon » : un visiteur non connecté ne voit rien.
-- Pas de policy = refusé. Les colonnes modifiables sont limitées en section 7.

alter table public.profils            enable row level security;
alter table public.colocations        enable row level security;
alter table public.membres            enable row level security;
alter table public.depenses           enable row level security;
alter table public.depense_parts      enable row level security;
alter table public.remboursements     enable row level security;
alter table public.taches             enable row level security;
alter table public.tache_realisations enable row level security;
alter table public.articles_courses   enable row level security;
alter table public.messages           enable row level security;

-- profils --------------------------------------------------------------------
create policy "profils : lire le sien et ceux des colocataires"
  on public.profils for select to authenticated
  using (id = (select auth.uid()) or prive.partage_une_coloc(id));

create policy "profils : modifier le sien"
  on public.profils for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- colocations (création : RPC creer_colocation) ------------------------------
create policy "colocations : lues par leurs membres"
  on public.colocations for select to authenticated
  using (id in (select prive.mes_colocations()));

create policy "colocations : renommées par l'admin"
  on public.colocations for update to authenticated
  using (prive.est_admin(id))
  with check (prive.est_admin(id));

create policy "colocations : supprimées par l'admin"
  on public.colocations for delete to authenticated
  using (prive.est_admin(id));

-- membres (arrivées, départs, rôles : uniquement par RPC) --------------------
create policy "membres : lus par les colocataires"
  on public.membres for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "membres : chacun met à jour son dernier message lu"
  on public.membres for update to authenticated
  using (utilisateur_id = (select auth.uid()) and parti_le is null)
  with check (utilisateur_id = (select auth.uid()) and parti_le is null);

-- dépenses (création : RPC creer_depense) ------------------------------------
create policy "dépenses : lues par les membres"
  on public.depenses for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "dépenses : créées par un membre, payées par un membre actif"
  on public.depenses for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and cree_par = (select auth.uid())
    and prive.est_membre_actif(colocation_id, payeur_id)
  );

create policy "dépenses : modifiées par l'auteur ou l'admin"
  on public.depenses for update to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (cree_par = (select auth.uid()) or prive.est_admin(colocation_id))
  )
  with check (colocation_id in (select prive.mes_colocations()));

create policy "dépenses : supprimées par l'auteur ou l'admin"
  on public.depenses for delete to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (cree_par = (select auth.uid()) or prive.est_admin(colocation_id))
  );

-- parts de dépense (suivent leur dépense : pas de modification directe) -----
create policy "parts : lues par les membres"
  on public.depense_parts for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "parts : ajoutées par l'auteur de la dépense, pour des membres actifs"
  on public.depense_parts for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and prive.est_membre_actif(colocation_id, utilisateur_id)
    and exists (
      select 1 from public.depenses d
      where d.id = depense_id and d.cree_par = (select auth.uid())
    )
  );

-- remboursements ------------------------------------------------------------
create policy "remboursements : lus par les membres"
  on public.remboursements for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "remboursements : déclarés par le débiteur ou le créancier"
  on public.remboursements for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and cree_par = (select auth.uid())
    and (select auth.uid()) in (debiteur_id, crediteur_id)
  );

create policy "remboursements : annulés par l'auteur ou l'admin"
  on public.remboursements for delete to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (cree_par = (select auth.uid()) or prive.est_admin(colocation_id))
  );

-- tâches (« marquer comme faite » : RPC terminer_tache) ----------------------
create policy "tâches : lues par les membres"
  on public.taches for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "tâches : créées par un membre, confiées à un membre actif"
  on public.taches for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and cree_par = (select auth.uid())
    and prive.est_membre_actif(colocation_id, responsable_id)
  );

create policy "tâches : modifiées par l'auteur ou l'admin"
  on public.taches for update to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (cree_par = (select auth.uid()) or prive.est_admin(colocation_id))
  )
  with check (colocation_id in (select prive.mes_colocations()));

create policy "tâches : supprimées par l'auteur ou l'admin"
  on public.taches for delete to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (cree_par = (select auth.uid()) or prive.est_admin(colocation_id))
  );

create policy "historique des tâches : lu par les membres"
  on public.tache_realisations for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

-- courses (liste collaborative : tout membre peut tout faire) ---------------
create policy "courses : lues par les membres"
  on public.articles_courses for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "courses : ajoutées par un membre"
  on public.articles_courses for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and ajoute_par = (select auth.uid())
  );

create policy "courses : cochées ou modifiées par un membre"
  on public.articles_courses for update to authenticated
  using (colocation_id in (select prive.mes_colocations()))
  with check (colocation_id in (select prive.mes_colocations()));

create policy "courses : supprimées par un membre"
  on public.articles_courses for delete to authenticated
  using (colocation_id in (select prive.mes_colocations()));

-- messages ------------------------------------------------------------------
create policy "messages : lus par les membres"
  on public.messages for select to authenticated
  using (colocation_id in (select prive.mes_colocations()));

create policy "messages : envoyés par un membre en son nom"
  on public.messages for insert to authenticated
  with check (
    colocation_id in (select prive.mes_colocations())
    and auteur_id = (select auth.uid())
  );

create policy "messages : supprimés par l'auteur ou l'admin"
  on public.messages for delete to authenticated
  using (
    colocation_id in (select prive.mes_colocations())
    and (auteur_id = (select auth.uid()) or prive.est_admin(colocation_id))
  );


-- =============================================================================
-- 7. DROITS — ce que l'API accepte de modifier, colonne par colonne
-- =============================================================================
-- La RLS filtre les LIGNES ; les droits par colonne empêchent par exemple
-- un client de changer cree_par, colocation_id ou coche_par.

revoke all on all tables in schema public from anon, authenticated;

grant select                                           on public.profils to authenticated;
grant update (pseudo, avatar_chemin)                   on public.profils to authenticated;

grant select, delete                                   on public.colocations to authenticated;
grant update (nom)                                     on public.colocations to authenticated;

grant select                                           on public.membres to authenticated;
grant update (dernier_message_lu_id)                   on public.membres to authenticated;

grant select, delete                                   on public.depenses to authenticated;
grant insert (colocation_id, payeur_id, montant_centimes, description, date_depense, ticket_chemin)
                                                       on public.depenses to authenticated;
grant update (description, date_depense, ticket_chemin) on public.depenses to authenticated;

grant select                                           on public.depense_parts to authenticated;
grant insert (depense_id, colocation_id, utilisateur_id, montant_centimes)
                                                       on public.depense_parts to authenticated;

grant select, delete                                   on public.remboursements to authenticated;
grant insert (colocation_id, debiteur_id, crediteur_id, montant_centimes)
                                                       on public.remboursements to authenticated;

grant select, delete                                   on public.taches to authenticated;
grant insert (colocation_id, titre, frequence, responsable_id, prochaine_echeance)
                                                       on public.taches to authenticated;
grant update (titre, frequence)                        on public.taches to authenticated;

grant select                                           on public.tache_realisations to authenticated;

grant select, delete                                   on public.articles_courses to authenticated;
grant insert (colocation_id, libelle, quantite)        on public.articles_courses to authenticated;
grant update (libelle, quantite, coche)                on public.articles_courses to authenticated;

grant select, delete                                   on public.messages to authenticated;
grant insert (colocation_id, contenu)                  on public.messages to authenticated;

grant select                                           on public.soldes to authenticated;

-- Fonctions internes : seules celles appelées par les policies sont exécutables
revoke execute on all functions in schema prive from public;
grant execute on function
  prive.mes_colocations(),
  prive.est_membre_actif(uuid, uuid),
  prive.est_admin(uuid),
  prive.partage_une_coloc(uuid),
  prive.uuid_ou_null(text)
to authenticated;

-- RPC : réservées aux utilisateurs connectés
revoke execute on function
  public.creer_colocation(text),
  public.rejoindre_colocation(text),
  public.regenerer_code(uuid),
  public.retirer_membre(uuid, uuid),
  public.quitter_colocation(uuid),
  public.creer_depense(uuid, uuid, integer, text, date, uuid[], integer[], text),
  public.terminer_tache(uuid)
from public, anon;

grant execute on function
  public.creer_colocation(text),
  public.rejoindre_colocation(text),
  public.regenerer_code(uuid),
  public.retirer_membre(uuid, uuid),
  public.quitter_colocation(uuid),
  public.creer_depense(uuid, uuid, integer, text, date, uuid[], integer[], text),
  public.terminer_tache(uuid)
to authenticated;


-- =============================================================================
-- 8. STORAGE — buckets privés (accès par URL signée)
-- =============================================================================
-- tickets : <colocation_id>/<fichier>   avatars : <utilisateur_id>/<fichier>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('tickets', 'tickets', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "tickets : lus par les membres de la coloc"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'tickets'
    and prive.uuid_ou_null((storage.foldername(name))[1]) in (select prive.mes_colocations())
  );

create policy "tickets : envoyés par les membres de la coloc"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'tickets'
    and prive.uuid_ou_null((storage.foldername(name))[1]) in (select prive.mes_colocations())
  );

create policy "tickets : supprimés par celui qui les a envoyés"
  on storage.objects for delete to authenticated
  using (bucket_id = 'tickets' and owner_id = (select auth.uid())::text);

create policy "avatars : lus par soi et ses colocataires"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or prive.partage_une_coloc(prive.uuid_ou_null((storage.foldername(name))[1]))
    )
  );

create policy "avatars : envoyés dans son propre dossier"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars : remplacés dans son propre dossier"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars : supprimés dans son propre dossier"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );


-- =============================================================================
-- 9. REALTIME
-- =============================================================================
-- Les évènements INSERT/UPDATE sont filtrés par la RLS de chaque abonné.
-- Côté Flutter, on filtre en plus par coloc : filter colocation_id=eq.<id>.

alter publication supabase_realtime
  add table public.messages, public.articles_courses, public.taches;
