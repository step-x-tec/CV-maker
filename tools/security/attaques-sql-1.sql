\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
\pset tuples_only on
insert into public.cvs(user_id,title,data,is_public,share_token) values (:'B','cv de B','{"p":{"name":"Secret B"}}',false,'tokB') ;
insert into public.payments(transaction_id,user_id,plan,amount,status) values ('TXB',:'B','pro',5000,'success');
\echo ##### 1
set role authenticated; select set_config('app.uid',:'A',false);
do $$ begin
  begin update public.profiles set is_admin=true, admin_role='owner' where id=auth.uid(); raise notice 'is_admin UPDATE: sans erreur'; exception when others then raise notice 'is_admin: BLOQUÉ (%)', sqlerrm; end;
  begin update public.profiles set plan='pro', plan_expires_at=now()+interval '5 years' where id=auth.uid(); raise notice 'plan UPDATE: sans erreur'; exception when others then raise notice 'plan: BLOQUÉ (%)', sqlerrm; end;
  begin update public.profiles set is_banned=false, exports_used=0, ai_used_today=0 where id=auth.uid(); raise notice 'quotas UPDATE: sans erreur'; exception when others then raise notice 'quotas: BLOQUÉ (%)', sqlerrm; end;
end $$;
reset role;
select 'état A après attaque: ', is_admin, admin_role, plan from public.profiles where id=:'A';
\echo ##### 2. A lit les données de B
set role authenticated; select set_config('app.uid',:'A',false);
select 'cvs de B visibles par A:', count(*) from public.cvs where user_id=:'B';
select 'profil de B visible:', count(*) from public.profiles where id=:'B';
select 'paiements de B visibles:', count(*) from public.payments where user_id=:'B';
\echo ##### 3. A modifie/supprime le CV de B
with u as (update public.cvs set title='piraté' where user_id=:'B' returning 1) select 'update cv B:', count(*) from u;
with d as (delete from public.cvs where user_id=:'B' returning 1) select 'delete cv B:', count(*) from d;
\echo ##### 4. paiement / licence
do $$ begin begin insert into public.payments(transaction_id,user_id,plan,amount,status) values ('TXFAKE',auth.uid(),'pro',5000,'success'); raise notice 'INSERT payment: AUTORISÉ !!'; exception when others then raise notice 'insert payment: BLOQUÉ'; end; end $$;
do $$ begin begin update public.payments set status='success' where user_id=auth.uid(); raise notice 'update payment: sans erreur'; exception when others then raise notice 'update payment: BLOQUÉ'; end; end $$;
\echo ##### 5. jeton public dupliqué
do $$ begin begin insert into public.cvs(user_id,title,data,is_public,share_token) values (auth.uid(),'x','{}',true,'tokB'); raise notice 'jeton dupliqué: AUTORISÉ'; exception when others then raise notice 'jeton dupliqué: BLOQUÉ (%)', sqlerrm; end; end $$;
\echo ##### 6. usurpation user_id
do $$ begin begin insert into public.cvs(user_id,title,data) values ('bbbbbbbb-0000-0000-0000-000000000002','usurpé','{}'); raise notice 'usurpation: AUTORISÉ !!'; exception when others then raise notice 'usurpation: BLOQUÉ'; end; end $$;
reset role;
