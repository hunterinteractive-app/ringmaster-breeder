begin;
do $$ declare n integer; begin
 select count(*) into n from public.varieties v join public.breeds b on b.id=v.breed_id
 where b.name='Mini Lop' and v.name in ('Chinchilla','Pointed White','Frosted Pearl','Steel') and v.is_recognized and v.standard_reference is not null;
 if n<>4 then raise exception 'Mini Lop recognition failed'; end if;
 if (select count(*) from public.varieties v join public.breeds b on b.id=v.breed_id where b.name='Giant Angora' and v.standard_reference is not null)<>2 then raise exception 'Giant Angora inherited invalid shared colors'; end if;
 if not exists(select 1 from public.varieties v join public.breeds b on b.id=v.breed_id where b.name='French Lop' and v.name='Otter Group (COD)' and v.standard_reference is null) then raise exception 'COD incorrectly promoted'; end if;
 if exists(select 1 from public.varieties v join public.breeds b on b.id=v.breed_id where b.name='English Angora' and v.name='Broken (COD)') then raise exception 'English Angora COD returned'; end if;
 insert into public.varieties(breed_id,name,is_recognized) select id,'Fixture custom color',false from public.breeds where species='rabbit' and name='Mini Lop';
 if exists(select 1 from public.varieties where name='Fixture custom color' and is_recognized) then raise exception 'Custom color promoted'; end if;
end $$;
rollback;
