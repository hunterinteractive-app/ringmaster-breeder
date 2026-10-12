-- Only service_role can execute; definer access is required to verify auth.users.
alter function public.resolve_calendar_subscription(text) security definer;
