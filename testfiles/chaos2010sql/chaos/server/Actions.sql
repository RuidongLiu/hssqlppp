/*
================================================================================

= Actions
*/
select new_module('actions', 'server');
/*
== Testing

for testing purposes sometimes want to make a given nondeterministic
action always fail or always succeed.

The categories are:
castle disappear
gooey blob spread
attack
ranged attack
resist: decree, lightning, subversion
cast spell

you have to set the override each time you want to override something

*/

create domain random_test text check (value in
       ('disappear', 'spread', 'attack',
        'ranged_attack', 'resist', 'cast',
        'bonus','break_engaged'));

create table test_action_overrides (
  override random_test,
  setting bool
);
select set_relvar_type('test_action_overrides', 'data');

create function action_rig_action_success(poverride random_test,
       psetting boolean) returns void as $$
begin
  insert into test_action_overrides (override, setting)
    values (poverride, psetting);
end;
$$ language plpgsql volatile;

select add_key('test_action_overrides', 'override');

/*
== random numbers
run all random tests through this, so that we can hook into them
during testing.
*/
create function check_random_success(t random_test, successPercentage int)
  returns boolean as $$
declare
  o boolean;
begin
  o := (select setting from test_action_overrides
       where override = t);
  if o is null then --normal random
    return (random() * 100) < successPercentage;
  else --overriden
    delete from test_action_overrides
      where override = t;
    return o;
  end if;
end;
$$ language plpgsql volatile;

create function min(integer, integer) returns integer as $$
  select min(n) from (select $1 as n union select $2 as n) as a;
$$ language sql immutable;

create function max(integer, integer) returns integer as $$
  select max(n) from (select $1 as n union select $2 as n) as a;
$$ language sql immutable;

create function limit_chance(integer) returns integer as $$
  select max(10, min($1, 100));
$$ language sql immutable;
