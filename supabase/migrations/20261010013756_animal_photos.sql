alter table public.animals add column photo_path text;
alter table public.animals add constraint animal_photo_own_path check (photo_path is null or split_part(photo_path,'/',1)=id::text);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('animal_photos','animal_photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy family_photo_read on storage.objects for select to authenticated using(bucket_id='animal_photos' and breeder_private.attachment_access(name));
create policy family_photo_insert on storage.objects for insert to authenticated with check(bucket_id='animal_photos' and breeder_private.attachment_access(name));
create policy family_photo_delete on storage.objects for delete to authenticated using(bucket_id='animal_photos' and breeder_private.attachment_access(name));
