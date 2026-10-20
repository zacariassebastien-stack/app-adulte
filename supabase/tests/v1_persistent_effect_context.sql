-- Disposable local database only. This test changes no historical snapshot.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if; end; $$;
create function pg_temp.check_effect(ok boolean, message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'TEST FAILED: %',message; end if; end; $$;
create function pg_temp.effect_card(id text, direction text default 'FAIRE', stage integer default 2)
returns jsonb language sql as $$
 select jsonb_build_object('concept_id',id,'resolved_action',jsonb_build_object(
   'stage_id',id||'.stage.'||stage,'direction',direction,
   'actor_player_ids',jsonb_build_array(case when direction='FAIRE' then 'owner' else 'partner' end),
   'target_player_ids',case when id='042' then '["owner","partner"]'::jsonb
     else jsonb_build_array(case when direction='FAIRE' then 'partner' else 'owner' end) end,
   'action_text','Frozen stage '||stage,
   'parameters',jsonb_build_object('duration_actions',3,'persistent_instruction','Frozen instruction')));
$$;
do $$
declare active jsonb; saved jsonb; id text; direction text; n integer;
begin
 foreach id in array array['033','034','035','061','062','063'] loop
   foreach direction in array array['FAIRE','RECEVOIR'] loop
     active:=public.v4_advance_persistent_effects('[]',jsonb_build_array(pg_temp.effect_card(id,direction)));
     perform pg_temp.check_effect(active#>>'{0,remaining_actions}'='3','activation excluded');
     perform pg_temp.check_effect(active#>>'{0,target_player_id}'=case when id in ('033','061')
       then case when direction='FAIRE' then 'owner' else 'partner' end
       else case when direction='FAIRE' then 'partner' else 'owner' end end,'effect bearer');
     saved:=active;
     perform pg_temp.check_effect(active#>>'{0,stage_id}'=id||'.stage.2','stage retained');
     perform pg_temp.check_effect(active#>>'{0,actor_player_ids,0}'=case when direction='FAIRE' then 'owner' else 'partner' end,'executor retained');
     for n in 1..3 loop
       active:=public.v4_advance_persistent_effects(active,'[{"concept_id":"001","resolved_action":{"parameters":{}}}]');
       if n<3 then
         perform pg_temp.check_effect((active#>>'{0,remaining_actions}')::integer=3-n,'action countdown');
         perform pg_temp.check_effect(active#>>'{0,stage_id}'=saved#>>'{0,stage_id}','context survives tick');
       else perform pg_temp.check_effect(active='[]','expires after third action'); end if;
     end loop;
   end loop;
 end loop;
 active:=public.v4_advance_persistent_effects('[]',jsonb_build_array(pg_temp.effect_card('042')));
 perform pg_temp.check_effect(jsonb_array_length(active)=2 and active#>>'{0,unit}'='turns','mutual sexting');
 saved:=active;
 -- Reading/serializing the canonical value does not advance it.
 perform pg_temp.check_effect(saved::text::jsonb=active,'reconnect preserves value');
 for n in 1..3 loop
   active:=public.v4_advance_persistent_effects(active,
     '[{"concept_id":"001","resolved_action":{"parameters":{}}},{"concept_id":"003","resolved_action":{"parameters":{}}}]');
   if n<3 then perform pg_temp.check_effect((active#>>'{0,remaining_actions}')::integer=3-n,'multi-action is one turn');
   else perform pg_temp.check_effect(active='[]','sexting expires after three rounds'); end if;
 end loop;
 -- Even another action in the activation round cannot consume a Sexting turn.
 active:=public.v4_advance_persistent_effects('[]',jsonb_build_array(pg_temp.effect_card('042'),pg_temp.effect_card('034')));
 perform pg_temp.check_effect((select bool_and((e->>'remaining_actions')::integer=3) from jsonb_array_elements(active) e where e->>'card_id'='042'),'activation round excluded');
 -- Legacy payloads, including retired 060, remain readable and expire naturally.
 active:=public.v4_advance_persistent_effects('[{"card_id":"060","target_player_id":"owner","remaining_actions":1}]',jsonb_build_array(pg_temp.effect_card('034')));
 perform pg_temp.check_effect(not exists(select 1 from jsonb_array_elements(active) e where e->>'card_id'='060'),'legacy effect expiry');
 raise notice 'PASS V1 persistent context, bearer, actions and turns';
end; $$;
rollback;
