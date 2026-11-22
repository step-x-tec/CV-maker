\pset tuples_only on
set role authenticated; select set_config('app.uid','aaaaaaaa-0000-0000-0000-000000000001',false);
select set_config('role','authenticated',false);
do $$ declare i int; ok int:=0; begin
  for i in 1..15 loop begin insert into public.support_tickets(user_id,subject,status) values (auth.uid(),'t'||i,'open'); ok:=ok+1; exception when others then null; end; end loop;
  raise notice 'tickets acceptés sur 15 tentatives: % (max 10)', ok;
  begin insert into public.testimonials(name,message,status) values ('x', repeat('a',2000),'pending'); raise notice 'message 2000 car.: ACCEPTÉ !!'; exception when others then raise notice 'message trop long: bloqué'; end;
  ok:=0; for i in 1..80 loop begin insert into public.feature_interest(feature,email,user_id) values ('lettre','a'||i||'@b.co',null); ok:=ok+1; exception when others then null; end; end loop;
  raise notice 'feature_interest anon acceptés sur 80: % (max 60)', ok;
  begin perform public.consume_ai_request(auth.uid()); raise notice 'consume_ai_request (chemin légitime): OK'; exception when others then raise notice 'consume_ai_request: ERREUR %', sqlerrm; end;
end $$;
reset role;
