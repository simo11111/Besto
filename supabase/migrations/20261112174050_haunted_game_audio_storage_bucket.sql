insert into storage.buckets(id,name,public,allowed_mime_types,file_size_limit)
values('game-assets','game-assets',true,array['audio/mpeg'],5242880)
on conflict(id) do update set public=true,allowed_mime_types=array['audio/mpeg'],file_size_limit=5242880;
