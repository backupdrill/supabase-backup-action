-- Small database for the action's own test run.
create table public.customers (
  id bigint generated always as identity primary key,
  email text not null unique,
  created_at timestamptz not null default now()
);
insert into public.customers (email)
select format('user%s@example.com', g) from generate_series(1, 300) g;

create table public.orders (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customers (id),
  total_cents int not null,
  created_at timestamptz not null default now()
);
insert into public.orders (customer_id, total_cents)
select (g % 300) + 1, (g * 37) % 10000 from generate_series(1, 1000) g;

analyze;
